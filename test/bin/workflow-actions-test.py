#!/usr/bin/env python3
"""Static security checks for GitHub Actions workflow references."""

import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
YQ = shutil.which("yq")
LOCAL_ACTION = re.compile(r"^\./(?!.*\$\{\{)\S+$")
PINNED_EXTERNAL = re.compile(
    r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*@[0-9a-fA-F]{40}$"
)
FULL_SHA = "0123456789abcdef0123456789abcdef01234567"


def workflow_files(root):
    return sorted(
        path
        for path in root.rglob("*")
        if path.is_file() and path.suffix in {".yaml", ".yml"}
    )


def parse_workflow(source):
    if YQ is None:
        raise RuntimeError("workflow action check requires managed tool 'yq'")
    parsed = subprocess.run(
        [YQ, "-c", "."],
        input=source,
        capture_output=True,
        text=True,
        check=False,
    )
    if parsed.returncode != 0:
        raise ValueError(f"invalid workflow YAML: {parsed.stderr.strip()}")
    return json.loads(parsed.stdout)


def action_references(source):
    references = []

    def walk(value, path):
        if isinstance(value, dict):
            for key, child in value.items():
                child_path = f"{path}.{key}"
                if key == "uses":
                    references.append((child_path, child))
                walk(child, child_path)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                walk(child, f"{path}[{index}]")

    walk(parse_workflow(source), "$")
    return references


def unpinned_external_actions(source):
    return [
        (path, action)
        for path, action in action_references(source)
        if not (
            isinstance(action, str)
            and (LOCAL_ACTION.fullmatch(action) or PINNED_EXTERNAL.fullmatch(action))
        )
    ]


class WorkflowActionPinTests(unittest.TestCase):
    def test_external_actions_use_full_commit_shas(self):
        workflows = workflow_files(REPO / ".github/workflows")
        self.assertTrue(workflows, "no GitHub Actions workflows found")
        violations = []
        for workflow in workflows:
            violations.extend(
                f"{workflow.relative_to(REPO)}:{path}: {action!r}"
                for path, action in unpinned_external_actions(
                    workflow.read_text(encoding="utf-8")
                )
            )
        self.assertEqual(violations, [])

    def test_parser_handles_quoted_keys_flow_mappings_and_comments(self):
        source = f"""
        # uses: owner/action@main
        jobs:
          quoted:
            steps:
              - "uses": "./local-action"
              - {{"uses": "owner/action@{FULL_SHA}"}}
              - uses: owner/action@{FULL_SHA} # release comment
        """
        self.assertEqual(unpinned_external_actions(source), [])

    def test_complete_scalar_rejects_expressions_mutable_refs_and_suffixes(self):
        source = (
            "jobs:\n"
            "  reusable:\n"
            "    uses: owner/repo/.github/workflows/check.yml@${{ github.sha }}\n"
            "  steps:\n"
            "    steps:\n"
            "      - uses: owner/action@main\n"
            f'      - {{"uses": "owner/action@{FULL_SHA}#suffix"}}\n'
            f'      - uses: "${{{{github.repository_owner}}}}/action@{FULL_SHA}"\n'
            f'      - uses: "owner/action@{FULL_SHA}${{{{github.ref}}}}"\n'
        )
        self.assertEqual(
            [action for _, action in unpinned_external_actions(source)],
            [
                "owner/repo/.github/workflows/check.yml@${{ github.sha }}",
                "owner/action@main",
                f"owner/action@{FULL_SHA}#suffix",
                f"${{{{github.repository_owner}}}}/action@{FULL_SHA}",
                f"owner/action@{FULL_SHA}${{{{github.ref}}}}",
            ],
        )

    def test_workflow_discovery_is_recursive_for_yml_and_yaml(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            paths = [root / "one.yml", root / "nested/deeper/two.yaml"]
            for path in paths:
                path.parent.mkdir(parents=True, exist_ok=True)
            paths[0].write_text("jobs: {}\n", encoding="utf-8")
            paths[1].write_text(
                "jobs: {call: {uses: owner/action@main}}\n", encoding="utf-8"
            )
            (root / "nested/ignored.yml.txt").write_text(
                "uses: owner/action@main\n", encoding="utf-8"
            )
            self.assertEqual(workflow_files(root), sorted(paths))
            violations = []
            for path in workflow_files(root):
                if found := unpinned_external_actions(path.read_text()):
                    violations.append((path.relative_to(root), found))
            self.assertEqual(
                violations,
                [
                    (
                        Path("nested/deeper/two.yaml"),
                        [("$.jobs.call.uses", "owner/action@main")],
                    )
                ],
            )


if __name__ == "__main__":
    unittest.main()
