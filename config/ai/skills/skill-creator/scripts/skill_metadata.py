#!/usr/bin/env python3
"""Shared metadata and path contracts for skill-creator scripts."""

import re
from pathlib import Path, PureWindowsPath

import yaml
from yaml.constructor import ConstructorError
from yaml.nodes import MappingNode


MAX_SKILL_NAME_LENGTH = 40
DESCRIPTION_TODO = (
    "[TODO: Complete and informative explanation of what the skill does and"
    " when to use it. Include WHEN to use this skill - specific scenarios,"
    " file types, or tasks that trigger it.]"
)
SKILL_NAME_PATTERN = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")


class _UniqueKeySafeLoader(yaml.SafeLoader):
    """Safe YAML loader that rejects ambiguous duplicate mapping keys."""

    def construct_mapping(self, node: yaml.Node, deep: bool = False) -> dict:
        if not isinstance(node, MappingNode):
            return super().construct_mapping(node, deep=deep)
        self.flatten_mapping(node)
        mapping = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            try:
                duplicate = key in mapping
            except TypeError as error:
                raise ConstructorError(
                    "while constructing a mapping",
                    node.start_mark,
                    "found an unhashable key",
                    key_node.start_mark,
                ) from error
            if duplicate:
                raise ConstructorError(
                    "while constructing a mapping",
                    node.start_mark,
                    f"found duplicate key ({key})",
                    key_node.start_mark,
                )
            mapping[key] = self.construct_object(value_node, deep=deep)
        return mapping


def validate_skill_name(skill_name: object) -> str:
    """Return a valid direct-child skill name or raise ``ValueError``."""
    if not isinstance(skill_name, str):
        raise ValueError(f"Name must be a string, got {type(skill_name).__name__}")
    if not skill_name:
        raise ValueError("Name must not be empty")
    if len(skill_name) > MAX_SKILL_NAME_LENGTH:
        raise ValueError(
            f"Name is too long ({len(skill_name)} characters). "
            f"Maximum is {MAX_SKILL_NAME_LENGTH} characters."
        )

    posix_name = Path(skill_name)
    windows_name = PureWindowsPath(skill_name)
    if (
        skill_name in {".", ".."}
        or posix_name.is_absolute()
        or windows_name.is_absolute()
        or len(posix_name.parts) != 1
        or len(windows_name.parts) != 1
    ):
        raise ValueError(
            f"Name '{skill_name}' must identify one direct child directory"
        )
    if skill_name.startswith("-") or skill_name.endswith("-") or "--" in skill_name:
        raise ValueError(
            f"Name '{skill_name}' cannot start/end with a hyphen or contain "
            "consecutive hyphens"
        )
    if SKILL_NAME_PATTERN.fullmatch(skill_name) is None:
        raise ValueError(
            f"Name '{skill_name}' must be lowercase hyphen-case "
            "(letters, digits, and hyphens only)"
        )
    return skill_name


def direct_child_skill_path(output_root: str | Path, skill_name: object) -> Path:
    """Construct a direct-child destination only after validating its name."""
    validated_name = validate_skill_name(skill_name)
    root = Path(output_root).resolve()
    skill_path = root / validated_name
    if skill_path.parent != root or skill_path.name != validated_name:
        raise ValueError(
            f"Name '{validated_name}' must identify one direct child directory"
        )
    return skill_path


def dump_frontmatter(name: str, description: str) -> str:
    """Serialize required frontmatter fields as safe YAML scalars."""
    return yaml.safe_dump(
        {"name": name, "description": description},
        allow_unicode=True,
        default_flow_style=False,
        sort_keys=False,
    ).rstrip("\n")


def _frontmatter_text(content: str) -> str:
    """Extract frontmatter while preserving every YAML input character."""
    if content.startswith("---\r\n"):
        yaml_start = 5
    elif content.startswith(("---\n", "---\r")):
        yaml_start = 4
    elif content.startswith("---"):
        raise ValueError("Invalid frontmatter format")
    else:
        raise ValueError("No YAML frontmatter found")

    line_start = yaml_start
    while line_start <= len(content):
        line_end = line_start
        while line_end < len(content) and content[line_end] not in "\r\n":
            line_end += 1
        if content[line_start:line_end] == "---":
            return content[yaml_start:line_start]
        if line_end == len(content):
            break
        if content.startswith("\r\n", line_end):
            line_start = line_end + 2
        else:
            line_start = line_end + 1
    raise ValueError("Invalid frontmatter format")


def parse_frontmatter(content: str) -> dict[object, object]:
    """Parse the first YAML frontmatter document exactly once and safely."""
    frontmatter_text = _frontmatter_text(content)
    try:
        loader = _UniqueKeySafeLoader(frontmatter_text)
        try:
            frontmatter = loader.get_single_data()
        finally:
            loader.dispose()
    except (
        yaml.YAMLError,
        AttributeError,
        LookupError,
        OverflowError,
        RecursionError,
        TypeError,
        ValueError,
    ) as error:
        raise ValueError(f"Invalid YAML in frontmatter: {error}") from error
    if not isinstance(frontmatter, dict):
        raise ValueError("Frontmatter must be a YAML mapping")
    return frontmatter
