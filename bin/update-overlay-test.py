#!/usr/bin/env python3

import contextlib
import io
import json
import os
import re
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace


SCRIPT = Path(__file__).with_name("update-overlay")
UPDATE_AGENTS = Path(__file__).with_name("update-agents")
UPGRADE_PROJECTS = Path(__file__).with_name("upgrade-projects")
UPGRADE = Path(__file__).with_name("upgrade")
BUILD = Path(__file__).parent.parent / "build"
MODULE = runpy.run_path(str(SCRIPT))
OverlayParser = MODULE["OverlayParser"]
OverlayUpdater = MODULE["OverlayUpdater"]
SourceTransaction = MODULE["SourceTransaction"]
load_update_manifest = MODULE["load_update_manifest"]
build_inventory = MODULE["build_inventory"]

VENDOR_HASH = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
HELPER_LINE = "  buildGoHelper = prev.buildGoModule.override { go = prev.go; };"
MULTILINE_HELPER = '''  useHelper =
    package:
    package.overrideAttrs (oldAttrs: {
      env = oldAttrs.env or { };
    });'''
OVERLAY = f'''final: prev:
let
{HELPER_LINE}
{MULTILINE_HELPER}
in
{{
  actual = prev.buildGoModule rec {{
    pname = "actual";
    version = "1.0.0";
    src = prev.fetchFromGitHub {{
      owner = "example";
      repo = "actual";
      tag = "v${{version}}";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    }};
    vendorHash = "{VENDOR_HASH}";
  }};
}}
'''


class OverlayParserTests(unittest.TestCase):
    def test_discovers_nested_ai_overlays_but_ignores_test_fixtures(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "ai").mkdir()
            (root / "tests").mkdir()
            (root / "root.nix").write_text(OVERLAY)
            (root / "ai" / "nested.nix").write_text(
                OVERLAY.replace('pname = "actual"', 'pname = "nested"')
                .replace("actual =", "nested =")
            )
            (root / "tests" / "ignored.nix").write_text(
                OVERLAY.replace('pname = "actual"', 'pname = "ignored"')
                .replace("actual =", "ignored =")
            )

            packages = OverlayParser(root).find_all_packages()
            self.assertIn("actual", packages)
            self.assertIn("nested", packages)
            self.assertNotIn("ignored", packages)

    def test_retired_ai_nix_flags_are_rejected(self):
        for flag in ("--ai-nix-dir", "--no-ai-nix", "--only-ai-nix", "--no-ai-nix-advice"):
            with self.subTest(flag=flag):
                result = subprocess.run(
                    [sys.executable, str(SCRIPT), flag, "--all"],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 2)
                self.assertIn("unrecognized arguments", result.stderr)

    def test_let_helper_does_not_absorb_output_packages(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            overlay_path = Path(temp_dir) / "overlay.nix"
            overlay_path.write_text(OVERLAY)

            parser = OverlayParser(Path(temp_dir))
            updater = OverlayUpdater()

            for helper_name, helper_block in (
                ("buildGoHelper", HELPER_LINE),
                ("useHelper", MULTILINE_HELPER),
            ):
                with self.subTest(helper=helper_name):
                    self.assertEqual(
                        parser._extract_package_block(OVERLAY, helper_name),
                        helper_block,
                    )
                    self.assertIsNone(parser.find_package(helper_name))

                    start_idx, end_idx = updater._find_package_block_lines(
                        OVERLAY, helper_name
                    )
                    self.assertEqual(
                        "\n".join(OVERLAY.splitlines()[start_idx : end_idx + 1]),
                        helper_block,
                    )

                    before = overlay_path.read_text()
                    changed = updater.set_dummy_hash(
                        overlay_path, helper_name, "vendorHash", VENDOR_HASH
                    )
                    self.assertFalse(changed)
                    self.assertEqual(overlay_path.read_text(), before)

            self.assertEqual(parser.find_package("actual").version, "1.0.0")


class UpdateInventoryTests(unittest.TestCase):
    def test_manifest_and_cli_inventory_cover_hidden_update_targets(self):
        root = SCRIPT.parent.parent
        try:
            manifest = load_update_manifest(root)
        except (RuntimeError, subprocess.SubprocessError, ValueError) as error:
            self.fail(f"manifest evaluation failed: {error}")
        required = {
            "agent-browser-source",
            "anvil-mcp",
            "bigpowers",
            "pi-artifacts",
            "pi-lens",
            "pi-mcp-adapter",
            "pi-subagentura",
            "pi-web-access",
            "rust-overlay",
            "ws",
            "git-ai",
            "llm-agents",
            "translate-tool",
        }
        self.assertTrue(required <= manifest.keys())
        self.assertIn("packages/pi-gallery/locks/pi-lens-package-lock.json", manifest["pi-lens"]["files"])
        self.assertIn("config/ai/catalog.nix", manifest["pi-mcp-adapter"]["files"])
        self.assertIn("packages/anvil-mcp/Cargo.lock", manifest["nelisp"]["files"])
        self.assertEqual(manifest["ws"]["package"], "ws")

        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--inventory", "--json"],
            capture_output=True,
            text=True,
            check=False,
            cwd=root,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        try:
            inventory = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            self.fail(f"inventory returned invalid JSON: {error}")
        names = [item["name"] for item in inventory["packages"]]
        self.assertEqual(len(names), len(set(names)))
        self.assertTrue(required <= set(names))
        self.assertTrue(all(item["inventoried"] for item in inventory["packages"]))
        by_name = {item["name"]: item for item in inventory["packages"]}
        relocated = {
            "browser-control-mcp",
            "claude-replay",
            "context-hub",
            "drafts-mcp-server",
            "gguf-tools",
            "hfdownloader",
            "llama-swap",
            "llm-mlx",
            "omlx",
            "rustdocs-mcp-server",
        }
        package_owned = {
            item["name"] for item in inventory["packages"] if item["source"] == "packages"
        }
        self.assertEqual(len(inventory["packages"]), 126)
        self.assertEqual(sum(item["managed"] for item in inventory["packages"]), 102)
        self.assertEqual(sum(not item["managed"] for item in inventory["packages"]), 24)
        self.assertEqual(package_owned, relocated)
        self.assertTrue(all(by_name[name]["managed"] for name in relocated))
        self.assertTrue(by_name["git-ai"]["managed"])
        self.assertEqual(by_name["git-ai"]["executor"], "update-agents")
        self.assertFalse(by_name["pi-lens"]["managed"])
        self.assertIsNone(by_name["pi-lens"]["executor"])
        for item in inventory["packages"]:
            for path in item["files"]:
                self.assertTrue((root / path).is_file(), (item["name"], path))

    def test_inventory_rejects_duplicate_overlay_owners(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "one.nix").write_text(OVERLAY)
            (root / "two.nix").write_text(OVERLAY)
            source = SimpleNamespace(name="test", parser=OverlayParser(root))
            with self.assertRaisesRegex(RuntimeError, "duplicate overlay owners for actual"):
                build_inventory([source], {}, root)

    def test_source_transaction_rolls_back_and_commit_preserves(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "overlay.nix"
            path.write_text("old\n")
            transaction = SourceTransaction()
            transaction.watch(path)
            path.write_text("broken\n")
            self.assertEqual(transaction.rollback(), 1)
            self.assertEqual(path.read_text(), "old\n")

            committed = SourceTransaction()
            committed.watch(path)
            path.write_text("new\n")
            committed.commit()
            committed.rollback_unless_committed()
            self.assertEqual(path.read_text(), "new\n")

    def test_failed_dependent_hash_rolls_back_complete_update(self):
        class FakeGitHubClient:
            def get_latest_release(self, _owner, _repo):
                return "v2.0.0"

        class FakeHashComputer:
            def __init__(self, _repo_dir):
                pass

            def compute_src_hash(self, _owner, _repo, _rev):
                return "sha256-CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC="

            def compute_vendor_hash(self, _package_name):
                return None

            def compute_cargo_hash(self, _package_name):
                return None

            def compute_npm_deps_hash(self, _package_name):
                return None

        with tempfile.TemporaryDirectory() as temp_dir:
            overlay = Path(temp_dir) / "overlay.nix"
            overlay.write_text(OVERLAY)
            before = overlay.read_text()
            globals_ = MODULE["main"].__globals__
            old_github = globals_["GitHubClient"]
            old_hash = globals_["HashComputer"]
            old_argv = sys.argv
            try:
                globals_["GitHubClient"] = FakeGitHubClient
                globals_["HashComputer"] = FakeHashComputer
                sys.argv = [str(SCRIPT), "--overlays-dir", temp_dir, "actual"]
                with contextlib.redirect_stdout(io.StringIO()):
                    status = MODULE["main"]()
            finally:
                globals_["GitHubClient"] = old_github
                globals_["HashComputer"] = old_hash
                sys.argv = old_argv
            self.assertEqual(status, 1)
            self.assertEqual(overlay.read_text(), before)


class IntegratedWorkflowTests(unittest.TestCase):
    def test_update_agents_rolls_back_failed_lock_and_source_transaction(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "repo"
            fake_bin = Path(temp_dir) / "bin"
            (root / "config/ai").mkdir(parents=True)
            (root / "overlays/ai").mkdir(parents=True)
            fake_bin.mkdir()
            for relative in (
                "flake.lock",
                "config/ai/flake.lock",
                "overlays/ai/package.nix",
            ):
                path = root / relative
                path.write_text(f"original {relative}\n")

            def executable(name, text):
                path = fake_bin / name
                path.write_text(text)
                path.chmod(0o700)

            executable("nix", """#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == flake && $2 == update ]]; then
  if [[ ${3:-} == --flake ]]; then
    echo portable-change >> config/ai/flake.lock
  else
    echo root-change >> flake.lock
  fi
elif [[ $1 == flake && $2 == check ]]; then
  exit 23
fi
""")
            executable("python", """#!/usr/bin/env bash
set -euo pipefail
echo overlay-change >> overlays/ai/package.nix
""")
            executable("nixfmt", "#!/usr/bin/env bash\nexit 0\n")

            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(["git", "-C", str(root), "add", "."], check=True)
            subprocess.run(
                ["git", "-C", str(root), "-c", "user.name=Test",
                 "-c", "user.email=test@example.invalid", "commit", "-qm", "baseline"],
                check=True,
            )
            env = {
                **os.environ,
                "NIX_CONFIG_DIR": str(root),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
            }
            result = subprocess.run(
                [str(UPDATE_AGENTS)], capture_output=True, text=True, env=env, check=False
            )
            self.assertEqual(result.returncode, 23)
            self.assertIn("rolled back incomplete source transaction", result.stderr)
            status = subprocess.run(
                ["git", "-C", str(root), "status", "--porcelain"],
                capture_output=True, text=True, check=True,
            )
            self.assertEqual(status.stdout, "")

    def test_active_commands_have_one_repository_update_transaction(self):
        root = SCRIPT.parent.parent
        update_agents = (root / "bin" / "update-agents").read_text()
        build = (root / "build").read_text()
        makefile = (root / "Makefile").read_text()
        upgrade = (root / "bin" / "upgrade").read_text()
        upgrade_projects = (root / "bin" / "upgrade-projects").read_text()
        switch = (root / "bin" / "switch").read_text()
        update_remote = (root / "bin" / "update-remote").read_text()
        active = "\n".join((update_agents, build, makefile, upgrade, upgrade_projects, switch, update_remote))

        for retired in (
            "AI_NIX_DIR",
            "NO_AI_NIX_OVERRIDE",
            "--override-input ai-nix",
            "--no-ai-nix",
            "--only-ai-nix",
            "src/ai-nix",
            "jwiegley/ai-nix",
        ):
            with self.subTest(retired=retired):
                self.assertNotIn(retired, active)

        self.assertIn('nix flake update "${ai_inputs[@]}"', update_agents)
        for required_input in (
            "git-ai",
            "llm-agents",
            "mcp-remote",
            "mcp-servers-nix",
            "pal-mcp-server",
            "pi-openai-server-compaction",
            "pi-quiet",
            "translate-tool",
        ):
            with self.subTest(required_input=required_input):
                self.assertIn(required_input, update_agents)
        self.assertIn(
            'nix flake update --flake ./config/ai "${ai_inputs[@]}"', update_agents
        )
        self.assertNotIn("\n    nixpkgs\n", update_agents)
        self.assertNotIn("\n    rust-overlay\n", update_agents)
        for manifest_only in (
            "agent-browser-source",
            "bigpowers",
            "pi-agent-browser-native",
            "pi-artifacts",
            "pi-dynamic-workflows",
            "pi-hashline-edit-pro",
            "pi-insights",
            "pi-lens",
            "pi-mcp-adapter",
            "pi-subagentura",
            "pi-web-access",
            "ponytail",
        ):
            with self.subTest(manifest_only=manifest_only):
                self.assertNotIn(f"\n    {manifest_only}\n", update_agents)
        self.assertIn(
            "python bin/update-overlay --all --overlays-dir overlays/ai", update_agents
        )
        self.assertEqual(update_agents.count('git_pull_clean "$config_dir"'), 1)
        self.assertIn("run_commit=false", update_agents)
        self.assertIn("run_switch=false", update_agents)
        self.assertIn("run_push=false", update_agents)
        self.assertIn("run_brew=false", update_agents)
        self.assertIn('commit -S -m "$message"', update_agents)
        self.assertIn("--switch/--push require --commit", update_agents)
        self.assertNotIn("git -C \"$repo\" add -A", update_agents)
        self.assertNotIn("commit_and_push_if_changed", update_agents)
        self.assertIn("bin/update-agents --all-inputs --brew", makefile)
        self.assertIn("if [[ $run_all_inputs == true ]]", update_agents)
        self.assertIn("        nix flake update\n", update_agents)
        manifest = load_update_manifest(root)
        expected_inputs = {
            name for name, target in manifest.items()
            if target.get("executor") == "update-agents"
        }
        block = re.search(r"ai_inputs=\((.*?)\n\)", update_agents, re.DOTALL)
        if block is None:
            self.fail("update-agents has no ai_inputs array")
        declared_inputs = {
            line.strip() for line in block.group(1).splitlines() if line.strip()
        }
        self.assertEqual(declared_inputs, expected_inputs)
        self.assertIn("transaction_baseline=", update_agents)
        self.assertIn("trap rollback_transaction EXIT", update_agents)
        self.assertNotIn('commit_if_changed "$config_dir" "Update AI agents" || true', update_agents)
        self.assertIn("refusing external action without a newly signed commit", update_agents)
        self.assertIn("set -euo pipefail", upgrade)
        self.assertRegex(upgrade, r"(?m)^\s*\./bin/update-agents --commit\s*$")
        self.assertIn('exec "$script_dir/upgrade-projects"', upgrade)
        self.assertNotIn("set +e", upgrade)
        self.assertNotIn("if [[ $?", upgrade_projects)
        self.assertIn("if (run_project_body", upgrade_projects)
        self.assertIn("failures=$((failures + 1))", upgrade_projects)
        self.assertIn("exit 1", upgrade_projects)
        self.assertIn('nix_flake_output_for_host "$host"', switch)
        self.assertIn('nixos-rebuild switch --flake ".#$output"', switch)
        self.assertNotIn("nixos-rebuild switch", update_remote)
        self.assertIn("&& switch", update_remote)
        self.assertNotIn("./bin/update-agents --no-switch --no-brew", upgrade)

    def test_overlay_manifests_are_explicit_and_inputs_do_not_leak_through_pkgs(self):
        root = SCRIPT.parent.parent
        composition = (root / "config/overlays.nix").read_text()
        root_declared = re.findall(r"\.\./overlays/([0-9][^/\s]+\.nix)", composition)
        root_actual = [path.name for path in (root / "overlays").glob("[0-9]*.nix")]
        self.assertEqual(len(root_declared), len(set(root_declared)))
        self.assertEqual(sorted(root_declared), sorted(root_actual))
        self.assertNotIn("readDir", composition)

        ai_composition = (root / "overlays/ai/default.nix").read_text()
        ai_declared = re.findall(r"import \./([0-9][^/\s]+\.nix)", ai_composition)
        ai_actual = [path.name for path in (root / "overlays/ai").glob("[0-9]*.nix")]
        self.assertEqual(len(ai_declared), len(set(ai_declared)))
        self.assertEqual(sorted(ai_declared), sorted(ai_actual))

        production_nix = [
            root / "flake.nix",
            *root.glob("config/**/*.nix"),
            *root.glob("flake/**/*.nix"),
            *root.glob("overlays/**/*.nix"),
        ]
        forbidden = (
            "pkgs.inputs",
            "prev.inputs",
            "final.inputs",
            "inherit (prev) inputs",
            "(_final: _prev: { inherit inputs; })",
        )
        for path in production_nix:
            text = path.read_text()
            for expression in forbidden:
                with self.subTest(path=path.relative_to(root), expression=expression):
                    self.assertNotIn(expression, text)

    def test_upgrade_projects_continues_and_returns_aggregate_failure(self):
        projects = (
            "src/category-theory/master",
            "src/ltl/coq",
            "src/notes/haskell",
            "src/org-jw",
            "src/pushme",
            "src/gitlib",
            "src/hours",
            "src/renamer",
            "src/simple-amount",
            "src/sizes",
            "src/three-partition",
            "src/trade-journal",
            "src/una",
            "src/comparable",
            "src/rag-client",
            "src/hf",
            "src/ledger/main",
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            home = temp / "home"
            fake_bin = temp / "bin"
            logs = temp / "logs"
            trace = temp / "trace"
            fake_bin.mkdir()
            for project in projects:
                directory = home / project
                directory.mkdir(parents=True)
                (directory / ".envrc").write_text("")
            for command in ("cabal", "cargo", "rag-client", "huggingface-cli"):
                path = fake_bin / command
                path.write_text(
                    "#!/usr/bin/env bash\n"
                    "printf '%s|%s|%s\\n' \"$(basename \"$0\")\" \"$PWD\" \"$*\" >> \"$UPGRADE_TRACE\"\n"
                    "[[ $(basename \"$0\") != rag-client ]] || exit 23\n"
                    "exit 0\n"
                )
                path.chmod(0o700)
            nix = fake_bin / "nix"
            nix.write_text(
                "#!/usr/bin/env bash\n"
                "printf 'nix|%s|%s\\n' \"$PWD\" \"$*\" >> \"$UPGRADE_TRACE\"\n"
                "[[ $PWD != */org-jw ]] || exit 19\n"
                "exit 0\n"
            )
            nix.chmod(0o700)
            result = subprocess.run(
                [str(UPGRADE_PROJECTS)],
                capture_output=True,
                text=True,
                check=False,
                env={
                    **os.environ,
                    "HOME": str(home),
                    "PATH": f"{fake_bin}:{os.environ['PATH']}",
                    "UPGRADE_LOG_DIR": str(logs),
                    "UPGRADE_TRACE": str(trace),
                },
            )
            self.assertEqual(result.returncode, 1)
            self.assertEqual(sum(line.endswith("FAIL") for line in result.stdout.splitlines()), 2)
            self.assertIn("2 failure(s)", result.stderr)

            events = [line.split("|", 2) for line in trace.read_text().splitlines()]
            nix_directories = {directory for command, directory, _ in events if command == "nix"}
            self.assertEqual(nix_directories, {str(home / project) for project in projects})
            command_counts = {
                command: sum(event[0] == command for event in events)
                for command in ("nix", "cabal", "cargo", "rag-client", "huggingface-cli")
            }
            self.assertEqual(
                command_counts,
                {"nix": 17, "cabal": 22, "cargo": 1, "rag-client": 1, "huggingface-cli": 1},
            )
            expected_logs = {
                "category-theory-build.log", "ltl-coq-build.log", "notes-haskell-build.log",
                "org-jw-build.log", "pushme-build.log", "gitlib-build.log", "hours-build.log",
                "renamer-build.log", "simple-amount-build.log", "sizes-build.log",
                "three-partition-build.log", "trade-journal-build.log", "una-build.log",
                "comparable-build.log", "rag-client-build.log", "hf-build.log", "ledger-build.log",
            }
            self.assertEqual({path.name for path in logs.iterdir()}, expected_logs)

    def test_host_routing_table_covers_system_and_shared_consumers(self):
        routing = SCRIPT.parent / "lib" / "host-routing.sh"
        result = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; normalize_nix_host Andoria-08; '
                'nix_flake_output_for_host vps; nix_flake_output_for_host vulcan',
                "host-routing-test",
                str(routing),
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertEqual(result.stdout.splitlines(), ["shared-work", "ovh-vps", "vulcan"])

        minimal_env = {**os.environ, "PATH": "/usr/bin:/bin"}
        build_help = subprocess.run(
            [str(BUILD), "--help"], capture_output=True, text=True, env=minimal_env, check=False
        )
        self.assertEqual(build_help.returncode, 0, build_help.stderr)
        self.assertIn("Usage: ./build", build_help.stdout)
        conflict = subprocess.run(
            [str(UPGRADE), "--host-only", "--projects-only"],
            capture_output=True,
            text=True,
            env=minimal_env,
            check=False,
        )
        self.assertEqual(conflict.returncode, 2)
        self.assertIn("mutually exclusive", conflict.stderr)

    def test_independent_ai_packages_are_owned_under_packages(self):
        root = SCRIPT.parent.parent
        ownership = {
            "30-ai-mcp.nix": ("ai-mcp.nix", ["pal-mcp-server", "rustdocs-mcp-server"]),
            "30-ai-python.nix": ("ai-python-extensions.nix", []),
            "30-ai-llm.nix": ("ai-llm.nix", ["aiperf", "guidellm", "omlx"]),
        }
        for overlay_name, (package_name, package_names) in ownership.items():
            overlay = (root / "overlays/ai" / overlay_name).read_text()
            package = (root / "packages" / package_name).read_text()
            self.assertIn(f"packages/{package_name}", overlay)
            for name in package_names:
                with self.subTest(overlay=overlay_name, package=name):
                    self.assertIn(f'pname = "{name}"', package)
                    self.assertNotIn(f'pname = "{name}"', overlay)

        python_overlay = (root / "overlays/ai/30-ai-python.nix").read_text()
        python_packages = (root / "packages/ai-python-extensions.nix").read_text()
        llm_mlx_package = (root / "packages/llm-mlx.nix").read_text()
        self.assertIn("./llm-mlx.nix", python_packages)
        self.assertIn('pname = "llm-mlx"', llm_mlx_package)
        self.assertNotIn('pname = "llm-mlx"', python_overlay)
        for name in (
            "mlx-speech",
            "mlx-embeddings",
            "dflash-mlx",
            "pyloudnorm",
            "phonemizer-fork",
            "espeakng-loader",
            "cohere-melody",
            "mlx-audio",
            "standard-distutils",
            "aiologic",
            "culsans",
        ):
            with self.subTest(overlay="30-ai-python.nix", package=name):
                self.assertIn(f'pname = "{name}"', python_packages)
                self.assertNotIn(f'pname = "{name}"', python_overlay)


if __name__ == "__main__":
    unittest.main()
