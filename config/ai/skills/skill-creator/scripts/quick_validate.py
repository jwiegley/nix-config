#!/usr/bin/env python3
"""Quick validation script for skills."""

import sys
from pathlib import Path

from skill_metadata import DESCRIPTION_TODO, parse_frontmatter, validate_skill_name


def validate_skill(skill_path):
    """Validate one skill's required frontmatter contract."""
    skill_path = Path(skill_path)

    skill_md = skill_path / "SKILL.md"
    if not skill_md.exists():
        return False, "SKILL.md not found"

    try:
        content = skill_md.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        return False, f"Could not read SKILL.md: {error}"
    try:
        frontmatter = parse_frontmatter(content)
    except ValueError as error:
        return False, str(error)

    if "name" not in frontmatter:
        return False, "Missing 'name' in frontmatter"
    if "description" not in frontmatter:
        return False, "Missing 'description' in frontmatter"

    name = frontmatter["name"]
    try:
        validate_skill_name(name)
    except ValueError as error:
        return False, str(error)
    if name != skill_path.name:
        return (
            False,
            f"Name '{name}' must match skill directory '{skill_path.name}'",
        )

    description = frontmatter["description"]
    if not isinstance(description, str):
        return False, f"Description must be a string, got {type(description).__name__}"
    description = description.strip()
    if not description:
        return False, "Description must not be empty"
    if description == DESCRIPTION_TODO:
        return False, "Description still contains the unchanged template TODO"
    if "<" in description or ">" in description:
        return False, "Description cannot contain angle brackets (< or >)"

    return True, "Skill is valid!"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python quick_validate.py <skill_directory>")
        sys.exit(1)

    valid, message = validate_skill(sys.argv[1])
    print(message)
    sys.exit(0 if valid else 1)
