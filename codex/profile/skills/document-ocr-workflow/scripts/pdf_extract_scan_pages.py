#!/usr/bin/env python3
"""Extract high-resolution scan pages and write a page provenance manifest."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from io import BytesIO
from pathlib import Path
from typing import Any

from PIL import Image, ImageFilter, ImageOps
from pypdf import PdfReader


def parse_page_spec(spec: str, page_count: int) -> list[int]:
    if spec.lower() == "all":
        return list(range(1, page_count + 1))
    pages: set[int] = set()
    for item in spec.split(","):
        item = item.strip()
        if not item:
            continue
        if "-" in item:
            start_text, end_text = item.split("-", 1)
            start, end = int(start_text), int(end_text)
            if start > end:
                raise ValueError(f"invalid descending range: {item}")
            pages.update(range(start, end + 1))
        else:
            pages.add(int(item))
    invalid = sorted(page for page in pages if page < 1 or page > page_count)
    if invalid:
        raise ValueError(f"page(s) outside 1-{page_count}: {invalid}")
    return sorted(pages)


def extract_largest_image(page: Any) -> tuple[Image.Image, str, int] | None:
    candidates: list[tuple[int, Image.Image, str]] = []
    for embedded in page.images:
        try:
            image = getattr(embedded, "image", None)
            if image is None:
                image = Image.open(BytesIO(embedded.data))
            image.load()
            image = image.copy()
            area = image.width * image.height
            candidates.append((area, image, str(getattr(embedded, "name", "embedded-image"))))
        except Exception:
            continue
    if not candidates:
        return None
    area, image, name = max(candidates, key=lambda candidate: candidate[0])
    return image, name, area


def run_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    executable = command[0].lower()
    if os.name == "nt" and executable.endswith((".cmd", ".bat")):
        return subprocess.run(
            subprocess.list2cmdline(command),
            shell=True,
            check=True,
            capture_output=True,
            text=True,
        )
    return subprocess.run(command, check=True, capture_output=True, text=True)


def resolve_pdftoppm(tool: str | None) -> str | None:
    if not tool:
        return None
    path = Path(tool).resolve()
    if path.suffix.lower() not in (".cmd", ".bat"):
        return str(path)
    candidates = (
        path.parent.parent / "native" / "poppler" / "Library" / "bin" / "pdftoppm.exe",
        path.parent.parent / "Library" / "bin" / "pdftoppm.exe",
    )
    for candidate in candidates:
        if candidate.exists():
            return str(candidate.resolve())
    return str(path)


def render_page(pdf: Path, page_number: int, dpi: int, tool: str) -> Image.Image:
    with tempfile.TemporaryDirectory(prefix="pdf-page-render-") as tmp:
        prefix = Path(tmp) / f"page-{page_number:04d}"
        run_command(
            [
                tool,
                "-f",
                str(page_number),
                "-l",
                str(page_number),
                "-singlefile",
                "-r",
                str(dpi),
                "-png",
                str(pdf),
                str(prefix),
            ]
        )
        rendered = prefix.with_suffix(".png")
        if not rendered.exists():
            raise RuntimeError("pdftoppm completed without producing an image")
        with Image.open(rendered) as image:
            image.load()
            return image.copy()


def estimate_deskew(image: Image.Image) -> float:
    try:
        import numpy as np
    except ImportError:
        return 0.0

    probe = image.convert("L")
    probe.thumbnail((900, 1300), Image.Resampling.LANCZOS)
    baseline = None
    best_score = -1.0
    best_angle = 0.0
    for angle in [value / 4 for value in range(-8, 9)]:
        rotated = probe.rotate(angle, resample=Image.Resampling.BILINEAR, expand=True, fillcolor=255)
        foreground = np.asarray(rotated) < 190
        projection = foreground.sum(axis=1).astype(float)
        score = float(np.square(np.diff(projection)).sum())
        if angle == 0:
            baseline = score
        if score > best_score:
            best_score = score
            best_angle = angle
    if baseline is None or best_score < baseline * 1.03 or abs(best_angle) < 0.25:
        return 0.0
    return best_angle


def preprocess_image(image: Image.Image, deskew: bool) -> tuple[Image.Image, float]:
    image = ImageOps.exif_transpose(image).convert("L")
    image = ImageOps.autocontrast(image, cutoff=0.5)
    angle = estimate_deskew(image) if deskew else 0.0
    if angle:
        image = image.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True, fillcolor=255)
    image = image.filter(ImageFilter.UnsharpMask(radius=1.0, percent=80, threshold=3))
    return image, angle


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract the largest embedded scan image from each PDF page, with Poppler fallback."
    )
    parser.add_argument("pdf", type=Path, help="Source PDF")
    parser.add_argument("--out-dir", type=Path, required=True, help="Directory for page PNGs")
    parser.add_argument("--pages", default="all", help="One-based pages, e.g. all, 1,3-5")
    parser.add_argument("--password", help="Password for an encrypted PDF")
    parser.add_argument("--preprocess", action="store_true", help="Apply grayscale, autocontrast, and sharpening")
    parser.add_argument("--deskew", action="store_true", help="Estimate and apply a mild deskew; implies preprocessing")
    parser.add_argument("--min-image-area", type=int, default=1_000_000, help="Minimum pixels for direct extraction")
    parser.add_argument("--dpi", type=int, default=300, help="Poppler fallback resolution (default: 300)")
    parser.add_argument("--pdftoppm", help="Explicit pdftoppm executable or wrapper")
    parser.add_argument("--manifest", type=Path, help="Manifest path (default: OUT-DIR/manifest.json)")
    parser.add_argument("--force", action="store_true", help="Overwrite existing page images")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = args.pdf.resolve()
    if not source.exists():
        print(f"error: file not found: {source}", file=sys.stderr)
        return 2

    reader = PdfReader(source)
    if reader.is_encrypted and (not args.password or reader.decrypt(args.password) == 0):
        print("error: encrypted PDF requires a valid password", file=sys.stderr)
        return 2

    try:
        selected_pages = parse_page_spec(args.pages, len(reader.pages))
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    args.out_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = args.manifest or args.out_dir / "manifest.json"
    pdftoppm = resolve_pdftoppm(args.pdftoppm or shutil.which("pdftoppm"))
    records: list[dict[str, Any]] = []

    for page_number in selected_pages:
        destination = args.out_dir / f"{source.stem}-p{page_number:04d}.png"
        record: dict[str, Any] = {
            "source_file": str(source),
            "source_page": page_number,
            "output": str(destination.resolve()),
        }
        try:
            if destination.exists() and not args.force:
                raise FileExistsError(f"output exists; use --force: {destination}")

            page = reader.pages[page_number - 1]
            embedded = extract_largest_image(page)
            if embedded and embedded[2] >= args.min_image_area:
                image, image_name, area = embedded
                method = "embedded-image"
                record["embedded_name"] = image_name
                record["embedded_area"] = area
            else:
                if not pdftoppm:
                    raise RuntimeError("no full-page raster found and pdftoppm is unavailable")
                image = render_page(source, page_number, args.dpi, pdftoppm)
                method = "pdftoppm"

            rotation = int(page.get("/Rotate", 0) or 0) % 360
            if rotation:
                image = image.rotate(-rotation, expand=True)

            deskew_angle = 0.0
            if args.preprocess or args.deskew:
                image, deskew_angle = preprocess_image(image, args.deskew)
            elif image.mode not in ("L", "RGB"):
                image = image.convert("RGB")

            image.save(destination, format="PNG", optimize=True)
            record.update(
                {
                    "status": "ok",
                    "method": method,
                    "width": image.width,
                    "height": image.height,
                    "rotation_applied": rotation,
                    "preprocessed": bool(args.preprocess or args.deskew),
                    "deskew_angle": deskew_angle,
                }
            )
        except Exception as exc:
            record.update({"status": "error", "error": f"{type(exc).__name__}: {exc}"})
        records.append(record)

    manifest = {
        "schema_version": 1,
        "source_file": str(source),
        "source_page_count": len(reader.pages),
        "selected_pages": selected_pages,
        "pages": records,
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(str(manifest_path.resolve()))
    return 2 if any(record["status"] == "error" for record in records) else 0


if __name__ == "__main__":
    sys.exit(main())
