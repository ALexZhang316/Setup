#!/usr/bin/env python3
"""
Quick validation script for skills - minimal version
"""

import re
import sys
from pathlib import Path

MAX_SKILL_NAME_LENGTH = 64


class FrontmatterError(ValueError):
    """Raised when a SKILL.md frontmatter block is not parseable."""


def parse_scalar(value):
    """Parse the simple scalar forms used by skill frontmatter."""
    value = value.strip()
    if not value:
        return None
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    if value in {"[]", "{}"}:
        return [] if value == "[]" else {}
    lowered = value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    return value


def collect_indented_block(lines, start_index):
    """Collect a nested YAML-ish block without fully parsing its contents."""
    collected = []
    index = start_index
    while index < len(lines):
        line = lines[index]
        if line.strip() and not line.startswith((" ", "\t")):
            break
        collected.append(line)
        index += 1
    return collected, index


def parse_block_scalar(lines, start_index, style):
    """Parse literal or folded block scalars for descriptions."""
    block_lines, index = collect_indented_block(lines, start_index)
    meaningful = [line for line in block_lines if line.strip()]
    if not meaningful:
        return "", index
    indents = [len(line) - len(line.lstrip(" ")) for line in meaningful]
    trim = min(indents)
    text_lines = [line[trim:] if len(line) >= trim else "" for line in block_lines]
    if style == ">":
        text = " ".join(line.strip() for line in text_lines if line.strip())
    else:
        text = "\n".join(text_lines).strip("\n")
    return text, index


def parse_frontmatter(frontmatter_text):
    """Parse the small YAML subset needed by quick skill validation."""
    result = {}
    lines = frontmatter_text.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            index += 1
            continue
        if line.startswith((" ", "\t")):
            raise FrontmatterError(f"nested value without a top-level key: {stripped!r}")

        match = re.match(r"^([A-Za-z0-9_-]+):(?:\s*(.*))?$", line)
        if not match:
            raise FrontmatterError(f"invalid frontmatter line: {line!r}")

        key, raw_value = match.groups()
        raw_value = "" if raw_value is None else raw_value
        index += 1

        if raw_value in {"|", ">"}:
            result[key], index = parse_block_scalar(lines, index, raw_value)
        elif raw_value == "":
            block_lines, next_index = collect_indented_block(lines, index)
            if any(block_line.strip() for block_line in block_lines):
                result[key] = {}
                index = next_index
            else:
                result[key] = None
        else:
            result[key] = parse_scalar(raw_value)

    return result


def validate_skill(skill_path):
    """Basic validation of a skill"""
    skill_path = Path(skill_path)

    skill_md = skill_path / "SKILL.md"
    if not skill_md.exists():
        return False, "SKILL.md not found"

    content = skill_md.read_text(encoding="utf-8-sig")
    if not content.startswith("---"):
        return False, "No YAML frontmatter found"

    match = re.match(r"^---\r?\n(.*?)\r?\n---", content, re.DOTALL)
    if not match:
        return False, "Invalid frontmatter format"

    frontmatter_text = match.group(1)

    try:
        frontmatter = parse_frontmatter(frontmatter_text)
        if not isinstance(frontmatter, dict):
            return False, "Frontmatter must be a YAML dictionary"
    except FrontmatterError as e:
        return False, f"Invalid YAML in frontmatter: {e}"

    allowed_properties = {"name", "description", "license", "allowed-tools", "metadata"}

    unexpected_keys = set(frontmatter.keys()) - allowed_properties
    if unexpected_keys:
        allowed = ", ".join(sorted(allowed_properties))
        unexpected = ", ".join(sorted(unexpected_keys))
        return (
            False,
            f"Unexpected key(s) in SKILL.md frontmatter: {unexpected}. Allowed properties are: {allowed}",
        )

    if "name" not in frontmatter:
        return False, "Missing 'name' in frontmatter"
    if "description" not in frontmatter:
        return False, "Missing 'description' in frontmatter"

    name = frontmatter.get("name", "")
    if not isinstance(name, str):
        return False, f"Name must be a string, got {type(name).__name__}"
    name = name.strip()
    if name:
        if not re.match(r"^[a-z0-9-]+$", name):
            return (
                False,
                f"Name '{name}' should be hyphen-case (lowercase letters, digits, and hyphens only)",
            )
        if name.startswith("-") or name.endswith("-") or "--" in name:
            return (
                False,
                f"Name '{name}' cannot start/end with hyphen or contain consecutive hyphens",
            )
        if len(name) > MAX_SKILL_NAME_LENGTH:
            return (
                False,
                f"Name is too long ({len(name)} characters). "
                f"Maximum is {MAX_SKILL_NAME_LENGTH} characters.",
            )

    description = frontmatter.get("description", "")
    if not isinstance(description, str):
        return False, f"Description must be a string, got {type(description).__name__}"
    description = description.strip()
    if description:
        if "<" in description or ">" in description:
            return False, "Description cannot contain angle brackets (< or >)"
        if len(description) > 1024:
            return (
                False,
                f"Description is too long ({len(description)} characters). Maximum is 1024 characters.",
            )

    return True, "Skill is valid!"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python quick_validate.py <skill_directory>")
        sys.exit(1)

    valid, message = validate_skill(sys.argv[1])
    print(message)
    sys.exit(0 if valid else 1)
