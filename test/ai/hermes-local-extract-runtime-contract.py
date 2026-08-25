#!/usr/bin/env python3
"""Load the managed extractor through Hermes Agent's real plugin runtime."""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path


def main() -> None:
    plugin_root = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="hermes-local-extract-runtime-") as directory:
        hermes_home = Path(directory)
        plugins = hermes_home / "plugins"
        bundled = hermes_home / "bundled-plugins"
        plugins.mkdir()
        bundled.mkdir()
        (plugins / "nix-managed-hermes-local-extract").symlink_to(
            plugin_root, target_is_directory=True
        )
        (hermes_home / "config.yaml").write_text(
            json.dumps({"plugins": {"enabled": ["web-local-extract"]}}),
            encoding="utf-8",
        )

        os.environ["HERMES_HOME"] = str(hermes_home)
        os.environ["HERMES_BUNDLED_PLUGINS"] = str(bundled)

        from agent.web_search_registry import get_provider
        from hermes_cli.plugins import PluginManager
        from tools.interrupt import is_interrupted

        assert isinstance(is_interrupted(), bool)

        manager = PluginManager(scope_key=str(hermes_home))
        manager.discover_and_load()
        provider = get_provider("local", scope=manager.scope_key)
        assert provider is not None
        assert provider.name == "local"
        assert provider.supports_extract() is True
        assert provider.supports_search() is False
        provider_module = sys.modules[provider.__class__.__module__]
        assert provider_module.is_interrupted is is_interrupted
        assert manager.unload()
        assert get_provider("local", scope=manager.scope_key) is None


if __name__ == "__main__":
    main()
