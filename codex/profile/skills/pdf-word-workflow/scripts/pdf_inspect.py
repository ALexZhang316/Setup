#!/usr/bin/env python3
"""Inspect PDF text layers and raster objects without modifying the source."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Iterable

from pypdf import PdfReader


def dereference(value: Any) -> Any:
    try:
        return value.get_object()
    except AttributeError:
        return value


def normalize_filter(value: Any) -> list[str]:
    value = dereference(value)
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return [str(item) for item in value]
    return [str(value)]


def iter_images(resources: Any, visited: set[tuple[int, int] | int]) -> Iterable[dict[str, Any]]:
    resources = dereference(resources)
    if not resources:
        return
    xobjects = dereference(resources.get("/XObject"))
    if not xobjects:
        return

    for name, reference in xobjects.items():
        identity: tuple[int, int] | int
        if hasattr(reference, "idnum"):
            identity = (reference.idnum, getattr(reference, "generation", 0))
        else:
            identity = id(reference)
        if identity in visited:
            continue
        visited.add(identity)

        obj = dereference(reference)
        subtype = str(obj.get("/Subtype", ""))
        if subtype == "/Image":
            width = int(obj.get("/Width", 0) or 0)
            height = int(obj.get("/Height", 0) or 0)
            yield {
                "name": str(name),
                "width": width,
                "height": height,
                "area": width * height,
                "bits_per_component": int(obj.get("/BitsPerComponent", 0) or 0),
                "color_space": str(dereference(obj.get("/ColorSpace")) or ""),
                "filters": normalize_filter(obj.get("/Filter")),
            }
        elif subtype == "/Form":
            yield from iter_images(obj.get("/Resources"), visited)


def inspect_pdf(path: Path, password: str | None, threshold: int) -> dict[str, Any]:
    result: dict[str, Any] = {
        "path": str(path.resolve()),
        "exists": path.exists(),
    }
    if not path.exists():
        result["error"] = "file not found"
        return result

    try:
        reader = PdfReader(path)
        result["encrypted"] = bool(reader.is_encrypted)
        if reader.is_encrypted:
            if not password or reader.decrypt(password) == 0:
                result["error"] = "encrypted PDF requires a valid password"
                return result

        pages: list[dict[str, Any]] = []
        class_counts = {"text": 0, "scan": 0, "hybrid": 0, "unknown": 0}
        for page_number, page in enumerate(reader.pages, start=1):
            text_error = None
            try:
                text = (page.extract_text() or "").strip()
            except Exception as exc:  # pypdf exposes malformed page errors here.
                text = ""
                text_error = f"{type(exc).__name__}: {exc}"

            images = list(iter_images(page.get("/Resources"), set()))
            largest = max(images, key=lambda image: image["area"], default=None)
            text_chars = len(text)
            if text_chars >= threshold and images:
                page_class = "hybrid"
            elif text_chars >= threshold:
                page_class = "text"
            elif images:
                page_class = "scan"
            else:
                page_class = "unknown"
            class_counts[page_class] += 1

            page_result: dict[str, Any] = {
                "page": page_number,
                "classification": page_class,
                "text_chars": text_chars,
                "image_count": len(images),
                "largest_image": largest,
                "rotation": int(page.get("/Rotate", 0) or 0),
            }
            if text_error:
                page_result["text_error"] = text_error
            pages.append(page_result)

        if class_counts["hybrid"]:
            overall = "hybrid"
        elif class_counts["text"] and (class_counts["scan"] or class_counts["unknown"]):
            overall = "mixed"
        elif class_counts["text"]:
            overall = "text"
        elif class_counts["scan"]:
            overall = "scan"
        else:
            overall = "unknown"

        result.update(
            {
                "page_count": len(pages),
                "classification": overall,
                "classification_counts": class_counts,
                "pages": pages,
            }
        )
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Report PDF page count, encryption, text-layer size, and raster objects."
    )
    parser.add_argument("pdf", nargs="+", type=Path, help="PDF file(s) to inspect")
    parser.add_argument("--password", help="Password used for encrypted inputs")
    parser.add_argument(
        "--text-threshold",
        type=int,
        default=20,
        help="Minimum non-whitespace characters for a page to count as text (default: 20)",
    )
    parser.add_argument("--json", dest="json_path", type=Path, help="Write the report to this JSON file")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = {
        "schema_version": 1,
        "documents": [inspect_pdf(path, args.password, args.text_threshold) for path in args.pdf],
    }
    output = json.dumps(
        report,
        ensure_ascii=False,
        indent=None if args.compact else 2,
    )
    if args.json_path:
        args.json_path.parent.mkdir(parents=True, exist_ok=True)
        args.json_path.write_text(output + "\n", encoding="utf-8")
    else:
        print(output)
    return 1 if any("error" in document for document in report["documents"]) else 0


if __name__ == "__main__":
    sys.exit(main())
