#!/usr/bin/env python3
"""Exercise the managed memory provider through Hermes Agent 0.20.5."""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path


class RecordingStore:
    def __init__(self, events):
        self.events = events

    def add_rows(self, rows):
        self.events.append(("rows", [(row["role"], row["content"]) for row in rows]))

    def close(self):
        self.events.append(("store_closed",))


class RecordingEmbedder:
    def __init__(self, events):
        self.events = events

    def close(self):
        self.events.append(("embedder_closed",))


def main() -> None:
    plugin_root = Path(sys.argv[1]).resolve()
    selector = "nix-managed-hermes-qdrant-memory"
    with tempfile.TemporaryDirectory(prefix="hermes-qdrant-runtime-") as directory:
        hermes_home = Path(directory)
        plugins = hermes_home / "plugins"
        plugins.mkdir()
        (plugins / selector).symlink_to(plugin_root, target_is_directory=True)
        config_path = hermes_home / "config.yaml"
        config_path.write_text(
            json.dumps(
                {
                    "memory": {"provider": selector},
                    "plugins": {
                        "qdrant": {
                            "collection": "assistant",
                            "connection": {"url": "https://qdrant.invalid"},
                        }
                    },
                }
            ),
            encoding="utf-8",
        )
        original_config = config_path.read_bytes()
        os.environ["HERMES_HOME"] = str(hermes_home)

        from agent.memory_manager import MemoryManager
        from plugins.memory import load_memory_provider
        from tools.registry import tool_error

        provider = load_memory_provider(selector, register_skills=False)
        assert provider is not None
        assert provider.name == "qdrant"
        assert not hasattr(provider, "post_setup")
        assert provider.config["collection"] == "assistant"
        assert config_path.read_bytes() == original_config
        assert provider.handle_tool_call("not-a-qdrant-tool", {}) == tool_error(
            "Unknown Qdrant memory tool: not-a-qdrant-tool"
        )

        events = []
        provider._store = RecordingStore(events)
        provider._embedder = RecordingEmbedder(events)
        provider._initialized = True
        provider._session_id = "session-1"
        provider._agent_context = "primary"
        provider._agent_workspace = "hera"
        provider._user_id = "johnw"

        manager = MemoryManager()
        manager.add_provider(provider)
        manager.sync_all("remember this", "I will", session_id="session-1")
        assert manager.flush_pending(timeout=5)
        manager.shutdown_all()
        assert manager.shutdown_drain_state["status"] == "drained"
        assert events == [
            ("rows", [("user", "remember this"), ("assistant", "I will")]),
            ("store_closed",),
            ("embedder_closed",),
        ]
        assert config_path.read_bytes() == original_config


if __name__ == "__main__":
    main()
