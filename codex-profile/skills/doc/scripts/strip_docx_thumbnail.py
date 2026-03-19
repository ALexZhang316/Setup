import argparse
import os
import tempfile
import xml.etree.ElementTree as ET
from os.path import abspath, dirname, expanduser
from zipfile import ZIP_DEFLATED, ZipFile

REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
CONTENT_TYPES_NS = "http://schemas.openxmlformats.org/package/2006/content-types"
THUMBNAIL_REL_TYPE = (
    "http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail"
)


def normalise_part_name(name: str) -> str:
    return name.replace("\\", "/").lstrip("/").lower()


def is_thumbnail_part(name: str) -> bool:
    return normalise_part_name(name).startswith("docprops/thumbnail.")


def strip_root_relationships(xml_bytes: bytes) -> tuple[bytes, int]:
    root = ET.fromstring(xml_bytes)
    removed = 0
    for rel in list(root):
        target = normalise_part_name(rel.get("Target", ""))
        rel_type = rel.get("Type", "")
        if rel_type == THUMBNAIL_REL_TYPE or is_thumbnail_part(target):
            root.remove(rel)
            removed += 1
    return ET.tostring(root, encoding="utf-8", xml_declaration=True), removed


def strip_content_type_overrides(xml_bytes: bytes) -> tuple[bytes, int]:
    root = ET.fromstring(xml_bytes)
    removed = 0
    override_tag = f"{{{CONTENT_TYPES_NS}}}Override"
    for child in list(root):
        if child.tag != override_tag:
            continue
        part_name = child.get("PartName", "")
        if is_thumbnail_part(part_name):
            root.remove(child)
            removed += 1
    return ET.tostring(root, encoding="utf-8", xml_declaration=True), removed


def sanitise_docx(input_path: str, output_path: str) -> tuple[int, int, int]:
    removed_parts = 0
    removed_relationships = 0
    removed_overrides = 0

    with ZipFile(input_path, "r") as src, ZipFile(
        output_path, "w", compression=ZIP_DEFLATED
    ) as dst:
        for info in src.infolist():
            name = info.filename
            if is_thumbnail_part(name):
                removed_parts += 1
                continue

            data = src.read(name)
            if name == "_rels/.rels":
                data, removed = strip_root_relationships(data)
                removed_relationships += removed
            elif name == "[Content_Types].xml":
                data, removed = strip_content_type_overrides(data)
                removed_overrides += removed

            dst.writestr(name, data)

    return removed_parts, removed_relationships, removed_overrides


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Remove embedded DOCX package thumbnails so Explorer uses the standard "
            "document icon/preview instead of a stale or blank thumbnail."
        )
    )
    parser.add_argument("input_path", help="Path to the source .docx file.")
    parser.add_argument(
        "--output",
        dest="output_path",
        default=None,
        help="Optional output path. Defaults to in-place update.",
    )
    args = parser.parse_args()

    input_path = abspath(expanduser(args.input_path))
    output_path = (
        abspath(expanduser(args.output_path)) if args.output_path else input_path
    )

    if not os.path.exists(input_path):
        raise SystemExit(f"Error: file not found: {input_path}")

    temp_dir = dirname(output_path) or "."
    with tempfile.NamedTemporaryFile(
        prefix="docx-thumb-clean-", suffix=".docx", dir=temp_dir, delete=False
    ) as tmp:
        temp_output = tmp.name

    try:
        removed_parts, removed_relationships, removed_overrides = sanitise_docx(
            input_path, temp_output
        )
        os.replace(temp_output, output_path)
    finally:
        if os.path.exists(temp_output):
            os.unlink(temp_output)

    print(
        "thumbnail_parts_removed="
        f"{removed_parts} root_relationships_removed={removed_relationships} "
        f"content_type_overrides_removed={removed_overrides} output={output_path}"
    )


if __name__ == "__main__":
    main()
