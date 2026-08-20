import argparse
import json
import os
import selectors
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

import tomllib


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise TypeError(f"{path}: catalog root is not an object")
    return value


def send(process: subprocess.Popen[bytes], message: dict) -> None:
    assert process.stdin is not None
    process.stdin.write(
        (json.dumps(message, separators=(",", ":")) + "\n").encode("utf-8")
    )
    process.stdin.flush()


class JsonlReader:
    def __init__(self, process: subprocess.Popen[bytes]) -> None:
        assert process.stdout is not None
        self.process = process
        self.stdout = process.stdout
        self.buffer = bytearray()
        os.set_blocking(self.stdout.fileno(), False)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.stdout, selectors.EVENT_READ)

    def close(self) -> None:
        self.selector.close()

    def receive(self, request_id: int, *, timeout: float = 15) -> dict:
        deadline = time.monotonic() + timeout
        while True:
            while b"\n" in self.buffer:
                line, _, remainder = self.buffer.partition(b"\n")
                self.buffer = bytearray(remainder)
                message = json.loads(line)
                if message.get("id") == request_id:
                    if "error" in message:
                        raise RuntimeError(
                            f"app-server request {request_id} failed: {message['error']}"
                        )
                    return message["result"]

            remaining = deadline - time.monotonic()
            if remaining <= 0 or not self.selector.select(remaining):
                raise TimeoutError(
                    f"timed out waiting for app-server response {request_id}"
                )
            chunk = os.read(self.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError(
                    f"app-server exited before response {request_id}: "
                    f"{self.process.poll()}"
                )
            self.buffer.extend(chunk)


def one_skill_entry(result: dict, cwd: Path) -> dict:
    entries = result.get("data")
    if not isinstance(entries, list) or len(entries) != 1:
        raise AssertionError(f"unexpected skills/list data: {entries!r}")
    entry = entries[0]
    if entry.get("cwd") != str(cwd) or entry.get("errors") != []:
        raise AssertionError(f"skills/list returned an invalid entry: {entry!r}")
    return entry


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("codex", type=Path)
    parser.add_argument("source_catalog", type=Path)
    parser.add_argument("managed_catalog", type=Path)
    parser.add_argument("managed_config", type=Path)
    parser.add_argument("managed_skill", type=Path)
    parser.add_argument("mcp_probe_config", type=Path)
    parser.add_argument("expected_catalog_path")
    parser.add_argument("expected_skill_description")
    args = parser.parse_args()

    source = load_json(args.source_catalog)
    managed = load_json(args.managed_catalog)
    source_models = source.get("models")
    managed_models = managed.get("models")
    if not isinstance(source_models, list) or not source_models:
        raise AssertionError("source catalog has no models")
    if not isinstance(managed_models, list) or not managed_models:
        raise AssertionError("managed catalog has no models")
    for index, model in enumerate(source_models):
        if not isinstance(model, dict):
            raise TypeError(f"source model {index} is not an object")
    for index, model in enumerate(managed_models):
        if not isinstance(model, dict):
            raise TypeError(f"managed model {index} is not an object")
    if {key: value for key, value in source.items() if key != "models"} != {
        key: value for key, value in managed.items() if key != "models"
    }:
        raise AssertionError("managed catalog changed root metadata")
    if [model.get("slug") for model in source_models] != [
        model.get("slug") for model in managed_models
    ]:
        raise AssertionError("managed catalog changed model membership or order")

    for index, (source_model, managed_model) in enumerate(
        zip(source_models, managed_models, strict=True)
    ):
        base_instructions = managed_model.get("base_instructions")
        if not isinstance(base_instructions, str) or not base_instructions:
            raise AssertionError(f"model {index} has invalid base_instructions")
        source_metadata = dict(source_model)
        managed_metadata = dict(managed_model)
        source_metadata.pop("base_instructions", None)
        managed_metadata.pop("base_instructions", None)
        if source_metadata != managed_metadata:
            raise AssertionError(f"managed catalog changed metadata for model {index}")

    with args.managed_config.open("rb") as stream:
        config = tomllib.load(stream)
    if config.get("model_catalog_json") != args.expected_catalog_path:
        raise AssertionError("managed config changed the installed catalog path")
    selection = {
        key: config.get(key)
        for key in ("model", "model_provider", "model_reasoning_effort")
    }
    if selection != {
        "model": "gpt-5.6-sol",
        "model_provider": "openai",
        "model_reasoning_effort": "ultra",
    }:
        raise AssertionError(f"managed Codex selection changed: {selection!r}")
    selected_slug = config.get("model")
    selected = [model for model in managed_models if model.get("slug") == selected_slug]
    if len(selected) != 1:
        raise AssertionError("managed config no longer selects one catalog model")
    selected_model = selected[0]
    if (
        config.get("model_auto_compact_token_limit")
        != selected_model.get("context_window") * 4 // 5
    ):
        raise AssertionError("managed auto-compaction selection changed")

    with tempfile.TemporaryDirectory(prefix="codex-catalog-smoke-") as temporary:
        root = Path(temporary)
        home = root / "home"
        codex_home = root / "codex-home"
        sqlite_home = root / "sqlite"
        workspace = root / "workspace"
        for path in (home, codex_home, sqlite_home, workspace):
            path.mkdir()
        shutil.copyfile(args.mcp_probe_config, codex_home / "config.toml")
        environment = {
            "BASH_ENV": "/forbidden",
            "CODEX_HOME": str(codex_home),
            "CODEX_INTERNAL_APP_SERVER_REMOTE_CONTROL_DISABLED": "1",
            "CODEX_SQLITE_HOME": str(sqlite_home),
            "DEFAULT_MODEL": "parent-poison",
            "GEMINI_API_KEY": "other-provider-sentinel",
            "GIT_AI_SOCKET": "/forbidden",
            "GIT_TRACE2_EVENT": "/forbidden",
            "HOME": str(home),
            "NODE_OPTIONS": "--trace-warnings",
            "NIX_SSL_CERT_FILE": "/managed-ca",
            "OPENAI_API_KEY": "typed-sentinel",
            "PATH": os.environ.get("PATH", ""),
            "PYTHONPATH": "/forbidden",
            "SSH_AUTH_SOCK": "/forbidden",
            "TMPDIR": str(root),
            "UNRELATED_SECRET": "unrelated-sentinel",
            "XDG_CACHE_HOME": str(root / "cache"),
            "XDG_CONFIG_HOME": str(root / "config"),
            "XDG_DATA_HOME": str(root / "data"),
            "XDG_STATE_HOME": str(root / "state"),
        }

        bundled = json.loads(
            subprocess.check_output(
                [args.codex, "debug", "models", "--bundled"],
                cwd=workspace,
                env=environment,
                text=True,
                timeout=15,
            )
        )
        bundled_models = bundled.get("models")
        if [model.get("slug") for model in bundled_models] != [
            model.get("slug") for model in managed_models
        ]:
            raise AssertionError(
                "Codex bundled catalog differs from managed model order"
            )
        for index, (bundled_model, managed_model) in enumerate(
            zip(bundled_models, managed_models, strict=True)
        ):
            if managed_model["base_instructions"] != bundled_model.get(
                "base_instructions"
            ):
                raise AssertionError(
                    f"model {index} instructions differ from the selected Codex serializer"
                )

        runtime_catalog = root / "runtime-catalog.json"
        runtime_description = "nix-catalog-transport-runtime-probe"
        if selected_model.get("description") == runtime_description:
            raise AssertionError("runtime catalog sentinel is not discriminating")
        runtime_models = [dict(model) for model in managed_models]
        runtime_selected = next(
            model for model in runtime_models if model.get("slug") == selected_slug
        )
        runtime_selected["description"] = runtime_description
        runtime_catalog.write_text(
            json.dumps(managed | {"models": runtime_models}), encoding="utf-8"
        )

        stderr_path = root / "app-server.stderr"
        with stderr_path.open("w+", encoding="utf-8") as stderr:
            process = subprocess.Popen(
                [
                    args.codex,
                    "-c",
                    f'model_catalog_json="{runtime_catalog}"',
                    "-c",
                    "analytics.enabled=false",
                    "-c",
                    "features.plugins=false",
                    "app-server",
                    "--stdio",
                    "--strict-config",
                ],
                cwd=workspace,
                env=environment,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=stderr,
                bufsize=0,
            )
            reader = JsonlReader(process)
            try:
                send(
                    process,
                    {
                        "method": "initialize",
                        "id": 1,
                        "params": {
                            "clientInfo": {
                                "name": "nix_catalog_transport",
                                "title": "Nix catalog transport test",
                                "version": "1.0.0",
                            }
                        },
                    },
                )
                reader.receive(1)
                send(process, {"method": "initialized"})
                send(
                    process,
                    {
                        "method": "model/list",
                        "id": 2,
                        "params": {"includeHidden": True},
                    },
                )
                models_result = reader.receive(2)
                if models_result.get("nextCursor") is not None:
                    raise AssertionError(
                        "model/list unexpectedly paginated the catalog"
                    )
                listed = [
                    model
                    for model in models_result.get("data", [])
                    if model.get("model") == selected_slug
                ]
                if len(listed) != 1:
                    raise AssertionError("model/list did not return the selected model")
                listed_model = listed[0]
                expected_projection = {
                    "displayName": selected_model["display_name"],
                    "description": runtime_description,
                    "defaultReasoningEffort": selected_model["default_reasoning_level"],
                    "supportedReasoningEfforts": [
                        level["effort"]
                        for level in selected_model["supported_reasoning_levels"]
                    ],
                }
                actual_projection = {
                    "displayName": listed_model.get("displayName"),
                    "description": listed_model.get("description"),
                    "defaultReasoningEffort": listed_model.get(
                        "defaultReasoningEffort"
                    ),
                    "supportedReasoningEfforts": [
                        level.get("reasoningEffort")
                        for level in listed_model.get("supportedReasoningEfforts", [])
                    ],
                }
                if actual_projection != expected_projection:
                    raise AssertionError("model/list changed selected model metadata")

                send(
                    process,
                    {
                        "method": "skills/list",
                        "id": 3,
                        "params": {"cwds": [str(workspace)], "forceReload": False},
                    },
                )
                initial_skills = one_skill_entry(reader.receive(3), workspace)
                if any(
                    skill.get("name") == "command-fess"
                    for skill in initial_skills.get("skills", [])
                ):
                    raise AssertionError(
                        "isolated Codex home already contains command-fess"
                    )

                skill_root = home / ".agents" / "skills"
                skill_root.mkdir(parents=True)
                shutil.copytree(args.managed_skill, skill_root / "command-fess")
                send(
                    process,
                    {
                        "method": "skills/list",
                        "id": 4,
                        "params": {"cwds": [str(workspace)], "forceReload": True},
                    },
                )
                refreshed_skills = one_skill_entry(reader.receive(4), workspace)
                matches = [
                    skill
                    for skill in refreshed_skills.get("skills", [])
                    if skill.get("name") == "command-fess"
                ]
                if len(matches) != 1 or not matches[0].get("enabled"):
                    raise AssertionError(
                        "Codex did not refresh the managed command skill"
                    )
                if matches[0].get("description") != args.expected_skill_description:
                    raise AssertionError("refreshed command skill metadata changed")

                send(
                    process,
                    {
                        "method": "mcpServerStatus/list",
                        "id": 5,
                        "params": {"detail": "toolsAndAuthOnly"},
                    },
                )
                # MCP startup includes the native client handshake and can exceed
                # the ordinary app-server response budget on loaded builders.
                mcp_result = reader.receive(5, timeout=60)
                if mcp_result.get("nextCursor") is not None:
                    raise AssertionError("MCP status unexpectedly paginated")
                statuses = mcp_result.get("data")
                if not isinstance(statuses, list) or len(statuses) != 1:
                    raise AssertionError(f"unexpected MCP statuses: {statuses!r}")
                status = statuses[0]
                if status.get("name") != "managed-environment-probe":
                    raise AssertionError(f"unexpected MCP status: {status!r}")
                server_info = status.get("serverInfo")
                if not isinstance(server_info, dict) or {
                    "name": server_info.get("name"),
                    "version": server_info.get("version"),
                } != {
                    "name": "nix-managed-environment-probe",
                    "version": "1",
                }:
                    raise AssertionError(
                        f"Codex did not initialize the managed MCP: {server_info!r}"
                    )
                tools = status.get("tools")
                if not isinstance(tools, dict) or set(tools) != {"environment_ok"}:
                    raise AssertionError(f"unexpected managed MCP tools: {tools!r}")
                if status.get("authStatus") != "unsupported":
                    raise AssertionError(f"unexpected MCP auth status: {status!r}")
                if status.get("resources") not in (None, []) or status.get(
                    "resourceTemplates"
                ) not in (None, []):
                    raise AssertionError(f"unexpected MCP resources: {status!r}")
            except Exception:
                stderr.flush()
                stderr.seek(0)
                diagnostic = stderr.read()
                if diagnostic:
                    print(diagnostic, end="", file=os.sys.stderr)
                raise
            finally:
                reader.close()
                if process.stdin is not None:
                    process.stdin.close()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)


if __name__ == "__main__":
    main()
