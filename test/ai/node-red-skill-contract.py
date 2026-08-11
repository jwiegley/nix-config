#!/usr/bin/env python3
"""Behavioral contract tests for the catalog Node-RED skill."""

import copy
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


DIGEST = "sha256:" + "a" * 64
FLOW_ID = "a1b2c3d4"


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def run_validator(validator, directory, name, value=None, raw=None):
    path = directory / name
    if raw is None:
        raw = json.dumps(
            value, ensure_ascii=True, allow_nan=False, separators=(",", ":")
        )
    path.write_text(raw, encoding="utf-8")
    return subprocess.run(
        [sys.executable, str(validator), str(path)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def valid_flow():
    return {
        "id": FLOW_ID,
        "label": "Office",
        "nodes": [
            {
                "id": "node1",
                "type": "inject",
                "z": FLOW_ID,
                "x": 100,
                "y": 100,
                "wires": [["node2"]],
            },
            {
                "id": "node2",
                "type": "debug",
                "z": FLOW_ID,
                "x": 300,
                "y": 100,
                "wires": [],
            },
        ],
        "configs": [{"id": "config1", "type": "server"}],
    }


def assert_validator_contract(root, temporary):
    validator = root / "scripts" / "validate_flow.py"
    envelope = {"baseDigest": DIGEST, "flow": valid_flow()}

    passing = {
        "selected-envelope.json": envelope,
        "selected-envelope-without-configs.json": {
            "baseDigest": DIGEST,
            "flow": {
                key: value for key, value in valid_flow().items() if key != "configs"
            },
        },
        "full-flow.json": [
            {"id": FLOW_ID, "type": "tab", "label": "Office"},
            *valid_flow()["nodes"],
            *valid_flow()["configs"],
        ],
    }
    for name, value in passing.items():
        result = run_validator(validator, temporary, name, value=value)
        check(
            result.returncode == 0,
            f"validator rejected {name}: {result.stdout}{result.stderr}",
        )

    for template in ("http_api_flow.json", "mqtt_flow.json"):
        result = subprocess.run(
            [
                sys.executable,
                str(validator),
                str(root / "assets" / "templates" / template),
            ],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        check(
            result.returncode == 0,
            f"validator rejected {template}: {result.stdout}{result.stderr}",
        )

    # The digest identifies the fetched predecessor, not the edited flow.
    edited = copy.deepcopy(envelope)
    edited["flow"]["label"] = "Edited after fetch"
    result = run_validator(validator, temporary, "edited-envelope.json", value=edited)
    check(
        result.returncode == 0,
        "validator incorrectly recomputed baseDigest after an edit",
    )

    invalid = {}

    bad = copy.deepcopy(envelope)
    bad["baseDigest"] = "sha256:ABC"
    invalid["bad-digest.json"] = bad

    bad = copy.deepcopy(envelope)
    bad["extra"] = True
    invalid["extra-envelope-key.json"] = bad

    for field in ("nodes", "configs"):
        bad = copy.deepcopy(envelope)
        bad["flow"][field] = {}
        invalid[f"bad-{field}.json"] = bad

    bad = copy.deepcopy(envelope)
    bad["flow"]["id"] = "UPPERCASE"
    invalid["bad-flow-id.json"] = bad

    bad = copy.deepcopy(envelope)
    bad["flow"]["nodes"].append("not-an-object")
    invalid["non-object-node.json"] = bad

    bad = copy.deepcopy(envelope)
    bad["flow"]["nodes"][0]["id"] = FLOW_ID
    invalid["flow-id-collision.json"] = bad

    bad = copy.deepcopy(envelope)
    bad["flow"]["nodes"][0]["z"] = "missing-tab"
    invalid["bad-container.json"] = bad

    bad = copy.deepcopy(envelope)
    bad["flow"]["nodes"][0]["wires"] = [["missing-node"]]
    invalid["dangling-wire.json"] = bad

    bad = copy.deepcopy(envelope)
    bad["flow"]["nodes"][0]["wires"] = [[FLOW_ID]]
    invalid["wire-to-tab.json"] = bad

    bad = copy.deepcopy(envelope)
    bad["flow"]["nodes"][0]["wires"] = [["config1"]]
    invalid["wire-to-config.json"] = bad

    bad = copy.deepcopy(envelope)
    bad["flow"]["nodes"][0] = {
        "id": "node1",
        "type": "inject",
        "wires": [],
    }
    invalid["envelope-node-without-container.json"] = bad

    invalid["metadata-lookalike.json"] = {"flows": []}
    invalid["ack-lookalike.json"] = {"ok": True, "id": FLOW_ID}

    for name, value in invalid.items():
        result = run_validator(validator, temporary, name, value=value)
        check(result.returncode != 0, f"validator accepted mutant {name}")

    raw_invalid = {
        "duplicate-key.json": (
            '{"baseDigest":"%s","baseDigest":"%s","flow":{}}' % (DIGEST, DIGEST)
        ),
        "nonfinite.json": '{"baseDigest":"%s","flow":{"id":"%s","nodes":[],"configs":[],"x":NaN}}'
        % (DIGEST, FLOW_ID),
        "oversize-envelope.json": json.dumps(envelope, separators=(",", ":"))
        + " " * (1024 * 1024),
        "overlong-integer.json": (
            '{"baseDigest":"%s","flow":{"id":"%s","nodes":[],"value":%s}}'
            % (DIGEST, FLOW_ID, "9" * 5000)
        ),
    }
    for name, raw in raw_invalid.items():
        result = run_validator(validator, temporary, name, raw=raw)
        check(result.returncode != 0, f"validator accepted mutant {name}")
        check(
            "Traceback" not in result.stderr, f"validator leaked a traceback for {name}"
        )


def write_admin_stub(path):
    path.write_text(
        f"""#!{sys.executable}
import json
import os
import stat
import sys
from pathlib import Path

flow_id = {FLOW_ID!r}
digest = {DIGEST!r}
args = sys.argv[1:]
with Path(os.environ["CALL_LOG"]).open("a", encoding="utf-8") as stream:
    stream.write(" ".join(args) + "\\n")

private_dirs = list(Path(os.environ["TMPDIR"]).glob("node-red-admin.*"))
if len(private_dirs) != 1 or stat.S_IMODE(private_dirs[0].stat().st_mode) != 0o700:
    print("stub: workflow directory is not private", file=sys.stderr)
    raise SystemExit(70)

flow = {{
    "id": flow_id,
    "label": "Office",
    "nodes": [{{"id": "node1", "type": "debug", "z": flow_id,
               "x": 100, "y": 100, "wires": []}}],
    "configs": [],
}}

if args == ["flows", "get"]:
    print(json.dumps({{"flows": [{{"id": flow_id, "label": "Office"}}]}},
                     ensure_ascii=True, separators=(",", ":")))
elif args == ["flow", "get", flow_id]:
    print(json.dumps({{"baseDigest": digest, "flow": flow}},
                     ensure_ascii=True, separators=(",", ":")))
elif args == ["flow", "put", flow_id]:
    envelope = json.load(sys.stdin)
    if set(envelope) != {{"baseDigest", "flow"}} or envelope["flow"]["id"] != flow_id:
        raise SystemExit(2)
    mode = os.environ["STUB_MODE"]
    if mode == "put-fails":
        print("node-red-admin: simulated failure", file=sys.stderr)
        raise SystemExit(1)
    if mode == "bad-ack":
        print(json.dumps({{"id": flow_id, "ok": True}}, separators=(",", ":")))
    else:
        print(json.dumps({{"ok": True, "id": flow_id}}, separators=(",", ":")))
else:
    raise SystemExit(2)
""",
        encoding="utf-8",
    )
    path.chmod(0o700)


def assert_workflow_contract(root, bash, temporary):
    reference = (root / "references" / "api_reference.md").read_text(encoding="utf-8")
    blocks = re.findall(r"```bash\n(.*?)\n```", reference, flags=re.DOTALL)
    check(len(blocks) == 1, "API reference must contain one canonical bash workflow")
    workflow = blocks[0]
    executable = [
        line.strip()
        for line in workflow.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    check(executable[0] == "set -euo pipefail", "workflow must start fail-closed")
    check('chmod 700 "$workdir"' in workflow, "workflow must enforce mode 0700")
    check(
        'cmp -s "$workdir/expected-ack.json" "$workdir/ack.json"' in workflow,
        "workflow must require the exact acknowledgement",
    )

    bin_dir = temporary / "bin"
    bin_dir.mkdir()
    write_admin_stub(bin_dir / "node-red-admin")

    expected_calls = {
        "put-fails": ["flows get", f"flow get {FLOW_ID}", f"flow put {FLOW_ID}"],
        "bad-ack": ["flows get", f"flow get {FLOW_ID}", f"flow put {FLOW_ID}"],
        "success": [
            "flows get",
            f"flow get {FLOW_ID}",
            f"flow put {FLOW_ID}",
            f"flow get {FLOW_ID}",
        ],
    }

    for mode, calls in expected_calls.items():
        case = temporary / mode
        case.mkdir()
        scratch = case / "tmp"
        scratch.mkdir()
        call_log = case / "calls.log"
        environment = os.environ.copy()
        environment.update(
            {
                "CALL_LOG": str(call_log),
                "PATH": os.pathsep.join(
                    [
                        str(bin_dir),
                        str(Path(sys.executable).parent),
                        environment.get("PATH", ""),
                    ]
                ),
                "STUB_MODE": mode,
                "TMPDIR": str(scratch),
            }
        )
        result = subprocess.run(
            [bash, "-c", workflow],
            cwd=root,
            env=environment,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        should_succeed = mode == "success"
        check(
            (result.returncode == 0) == should_succeed,
            f"workflow mode {mode} returned {result.returncode}: {result.stderr}",
        )
        actual_calls = call_log.read_text(encoding="utf-8").splitlines()
        check(
            actual_calls == calls,
            f"workflow mode {mode} calls {actual_calls}, expected {calls}",
        )
        check(
            list(scratch.glob("node-red-admin.*")) == [],
            f"workflow mode {mode} left sensitive temporary data behind",
        )


def main():
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} SKILL_ROOT BASH")
    root = Path(sys.argv[1]).resolve()
    bash = sys.argv[2]
    with tempfile.TemporaryDirectory(prefix="node-red-skill-contract.") as directory:
        temporary = Path(directory)
        assert_validator_contract(root, temporary)
        assert_workflow_contract(root, bash, temporary)
    print("node-red skill contract: ok")


if __name__ == "__main__":
    main()
