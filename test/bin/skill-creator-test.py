#!/usr/bin/env python3

import contextlib
import importlib
import io
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

import yaml


REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / "config/ai/skills/skill-creator/scripts"
sys.path.insert(0, str(SCRIPTS))
try:
    init_skill = importlib.import_module("init_skill")
    package_skill = importlib.import_module("package_skill")
    quick_validate = importlib.import_module("quick_validate")
    skill_metadata = importlib.import_module("skill_metadata")
finally:
    sys.path.pop(0)


def skill_document(metadata: object) -> str:
    frontmatter = yaml.safe_dump(metadata, sort_keys=False).rstrip("\n")
    return f"---\n{frontmatter}\n---\n\n# Test Skill\n"


def raw_skill_document(frontmatter: str) -> str:
    return f"---\n{frontmatter.rstrip()}\n---\n\n# Test Skill\n"


def write_skill(root: Path, name: str, content: str | None = None) -> Path:
    skill_path = root / name
    skill_path.mkdir(parents=True)
    if content is None:
        content = skill_document(
            {
                "name": name,
                "description": "Use this skill for focused test work.",
            }
        )
    (skill_path / "SKILL.md").write_text(content, encoding="utf-8")
    return skill_path


class SkillNameContractTests(unittest.TestCase):
    def test_accepts_valid_names_at_length_boundary(self) -> None:
        valid_names = [
            "skill",
            "skill-2",
            "2d-skill",
            "a" * skill_metadata.MAX_SKILL_NAME_LENGTH,
        ]

        for name in valid_names:
            with self.subTest(name=name):
                self.assertEqual(skill_metadata.validate_skill_name(name), name)

    def test_rejects_non_child_and_non_hyphen_case_names(self) -> None:
        invalid_names = [
            "",
            ".",
            "..",
            "../escape",
            "nested/skill",
            r"nested\skill",
            "/absolute-skill",
            r"C:\absolute-skill",
            "Uppercase",
            "under_score",
            "two--hyphens",
            "-leading",
            "trailing-",
            "a" * (skill_metadata.MAX_SKILL_NAME_LENGTH + 1),
        ]

        for name in invalid_names:
            with self.subTest(name=name), self.assertRaises(ValueError):
                skill_metadata.validate_skill_name(name)

        with self.assertRaisesRegex(ValueError, "must be a string"):
            skill_metadata.validate_skill_name(["not", "a", "scalar"])

    def test_initializer_rejects_escapes_before_creating_output(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="sc-", dir="/tmp"
        ) as temporary_directory:
            temporary = Path(temporary_directory)
            traversal_root = temporary / "traversal" / "root"
            absolute_root = temporary / "absolute" / "root"
            absolute_escape = temporary / "absolute-escape"
            self.assertLessEqual(
                len(str(absolute_escape)), skill_metadata.MAX_SKILL_NAME_LENGTH
            )

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                traversal_result = init_skill.init_skill("../escape", traversal_root)
                absolute_result = init_skill.init_skill(
                    str(absolute_escape), absolute_root
                )

            self.assertIsNone(traversal_result)
            self.assertIsNone(absolute_result)
            self.assertFalse(traversal_root.exists())
            self.assertFalse(absolute_root.exists())
            self.assertFalse(temporary.joinpath("traversal", "escape").exists())
            self.assertFalse(absolute_escape.exists())
            self.assertEqual(output.getvalue().count("direct child"), 2)

    def test_initializer_creates_exactly_one_direct_child(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory) / "skills"
            with contextlib.redirect_stdout(io.StringIO()):
                result = init_skill.init_skill("valid-skill", root)

            expected = root.resolve() / "valid-skill"
            self.assertEqual(result, expected)
            self.assertEqual(expected.parent, root.resolve())
            self.assertTrue(expected.joinpath("SKILL.md").is_file())


class FrontmatterValidationTests(unittest.TestCase):
    def assert_invalid(self, skill_path: Path, message: str) -> None:
        valid, validation_message = quick_validate.validate_skill(skill_path)
        self.assertFalse(valid, validation_message)
        self.assertIn(message, validation_message)

    def test_initializer_serializes_description_as_string(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            with contextlib.redirect_stdout(io.StringIO()):
                skill_path = init_skill.init_skill("generated-skill", root)
            assert skill_path is not None

            content = skill_path.joinpath("SKILL.md").read_text(encoding="utf-8")
            _, frontmatter_text, _ = content.split("---", 2)
            frontmatter = yaml.safe_load(frontmatter_text)

            self.assertIsInstance(frontmatter, dict)
            self.assertEqual(frontmatter["name"], "generated-skill")
            self.assertIsInstance(frontmatter["description"], str)
            self.assertEqual(
                frontmatter["description"], skill_metadata.DESCRIPTION_TODO
            )
            self.assert_invalid(skill_path, "unchanged template TODO")

    def test_accepts_valid_yaml_and_cr_lf_line_endings(self) -> None:
        endings = {"lf": "\n", "crlf": "\r\n", "cr": "\r"}
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            for suffix, line_ending in endings.items():
                name = f"valid-{suffix}"
                content = line_ending.join(
                    [
                        "---",
                        f"name: {name}",
                        "description: Use this skill for valid work.",
                        "---",
                        "",
                        "# Test Skill",
                        "",
                    ]
                )
                with self.subTest(line_ending=suffix):
                    skill_path = write_skill(root, name, content)

                    valid, message = quick_validate.validate_skill(skill_path)

                    self.assertTrue(valid, message)

    def test_rejects_malformed_and_non_mapping_yaml(self) -> None:
        cases = [
            ("name: broken\ndescription: [unterminated", "Invalid YAML"),
            ("- name\n- description", "YAML mapping"),
            (
                "name: duplicate-name\nname: duplicate-name\ndescription: Text",
                "duplicate key",
            ),
            (
                "name: duplicate-description\ndescription: First\ndescription: Second",
                "duplicate key",
            ),
            (
                'name: control-character\ndescription: "valid\vnot-valid"',
                "Invalid YAML",
            ),
            (
                'name: control-character-2\ndescription: "valid\fnot-valid"',
                "Invalid YAML",
            ),
            (
                'name: control-character-3\ndescription: "valid\x1cnot-valid"',
                "Invalid YAML",
            ),
            (
                'name: control-character-4\ndescription: "valid\x1dnot-valid"',
                "Invalid YAML",
            ),
            (
                'name: control-character-5\ndescription: "valid\x1enot-valid"',
                "Invalid YAML",
            ),
            (
                "name: malformed-map\ndescription: Text\nextra: !!map [a, b]",
                "Invalid YAML",
            ),
            (
                "name: malformed-set\ndescription: Text\nextra: !!set [a, b]",
                "Invalid YAML",
            ),
            (
                "name: malformed-timestamp\ndescription: !!timestamp []",
                "Invalid YAML",
            ),
            (
                "name: malformed-bool\ndescription: !!bool not-a-bool",
                "Invalid YAML",
            ),
            (
                "name: deeply-nested\ndescription: " + "[" * 600 + "]" * 600,
                "Invalid YAML",
            ),
        ]
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            for index, (frontmatter, expected_message) in enumerate(cases):
                with self.subTest(frontmatter=frontmatter):
                    skill_path = write_skill(
                        root,
                        f"malformed-{index}",
                        raw_skill_document(frontmatter),
                    )
                    self.assert_invalid(skill_path, expected_message)

    def test_rejects_missing_delimiter_and_required_fields(self) -> None:
        cases = [
            ("name: no-frontmatter\n", "No YAML frontmatter"),
            (
                raw_skill_document(
                    'description: "A description mentioning name: only."'
                ),
                "Missing 'name'",
            ),
            (
                raw_skill_document('name: missing-description\nnote: "description:"'),
                "Missing 'description'",
            ),
            ("---\nname: missing-close\ndescription: text\n", "frontmatter format"),
        ]
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            for index, (content, expected_message) in enumerate(cases):
                with self.subTest(content=content):
                    skill_path = write_skill(root, f"missing-{index}", content)
                    self.assert_invalid(skill_path, expected_message)

    def test_requires_exact_string_scalar_types(self) -> None:
        cases = [
            (
                {"name": ["scalar-types"], "description": "Text"},
                "Name must be a string",
            ),
            (
                {"name": True, "description": "Text"},
                "Name must be a string",
            ),
            (
                {"name": "scalar-types-2", "description": ["Text"]},
                "Description must be a string",
            ),
            (
                {"name": "scalar-types-3", "description": 3},
                "Description must be a string",
            ),
        ]
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            for index, (metadata, expected_message) in enumerate(cases):
                with self.subTest(metadata=metadata):
                    skill_path = write_skill(
                        root, f"scalar-types-{index}", skill_document(metadata)
                    )
                    self.assert_invalid(skill_path, expected_message)

    def test_reuses_name_contract_and_requires_directory_agreement(self) -> None:
        cases = [
            (
                "safe-directory",
                {"name": "Uppercase", "description": "Text"},
                "lowercase hyphen-case",
            ),
            (
                "safe-directory-2",
                {"name": "two--hyphens", "description": "Text"},
                "consecutive hyphens",
            ),
            (
                "actual-directory",
                {"name": "different-name", "description": "Text"},
                "must match skill directory",
            ),
            (
                "safe-directory-3",
                {
                    "name": "a" * (skill_metadata.MAX_SKILL_NAME_LENGTH + 1),
                    "description": "Text",
                },
                "Name is too long",
            ),
        ]
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            for directory, metadata, expected_message in cases:
                with self.subTest(metadata=metadata):
                    skill_path = write_skill(root, directory, skill_document(metadata))
                    self.assert_invalid(skill_path, expected_message)

    def test_rejects_empty_or_unchanged_description(self) -> None:
        cases = [
            ({"name": "empty-description", "description": "  "}, "must not be empty"),
            (
                {
                    "name": "template-description",
                    "description": skill_metadata.DESCRIPTION_TODO,
                },
                "unchanged template TODO",
            ),
        ]
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            for metadata, expected_message in cases:
                with self.subTest(metadata=metadata):
                    skill_path = write_skill(
                        root, metadata["name"], skill_document(metadata)
                    )
                    self.assert_invalid(skill_path, expected_message)

    def test_safe_loader_rejects_python_object_construction(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            marker = root / "unsafe-loader-ran"
            frontmatter = (
                "name: malicious-yaml\n"
                "description: !!python/object/apply:os.system\n"
                f"  - 'touch {marker}'"
            )
            skill_path = write_skill(
                root, "malicious-yaml", raw_skill_document(frontmatter)
            )

            self.assert_invalid(skill_path, "Invalid YAML")
            self.assertFalse(marker.exists())


class PackageSkillTests(unittest.TestCase):
    def test_packages_only_a_valid_matching_skill(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            skill_path = write_skill(root, "package-ready")
            output = root / "dist"

            with contextlib.redirect_stdout(io.StringIO()):
                archive = package_skill.package_skill(skill_path, output)

            self.assertEqual(archive, output.resolve() / "package-ready.zip")
            assert archive is not None
            with zipfile.ZipFile(archive) as packaged:
                self.assertIn("package-ready/SKILL.md", packaged.namelist())

    def test_refuses_malformed_and_unchanged_skills(self) -> None:
        cases = [
            (
                "malformed-package",
                raw_skill_document("name: malformed-package\ndescription: [broken"),
            ),
            (
                "template-package",
                skill_document(
                    {
                        "name": "template-package",
                        "description": skill_metadata.DESCRIPTION_TODO,
                    }
                ),
            ),
            (
                "mismatched-package",
                skill_document(
                    {
                        "name": "different-package",
                        "description": "A complete description.",
                    }
                ),
            ),
        ]
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            for index, (name, content) in enumerate(cases):
                with self.subTest(name=name):
                    skill_path = write_skill(root, name, content)
                    output = root / f"dist-{index}"
                    with contextlib.redirect_stdout(io.StringIO()):
                        archive = package_skill.package_skill(skill_path, output)

                    self.assertIsNone(archive)
                    self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
