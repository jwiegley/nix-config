#!/usr/bin/env python3
"""Behavioral URL-diagnostic redaction contract for exact Hermes 0.20.5."""

from __future__ import annotations

import asyncio
import json
import logging
import sys
from pathlib import Path


class DebugRecorder:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict]] = []

    def log_call(self, name: str, data: dict) -> None:
        self.calls.append((name, data))

    def save(self) -> None:
        pass


class LogRecorder(logging.Handler):
    def __init__(self) -> None:
        super().__init__()
        self.messages: list[str] = []

    def emit(self, record: logging.LogRecord) -> None:
        self.messages.append(record.getMessage())


class Provider:
    name = "contract-local"
    display_name = "Contract Local"

    def __init__(self, urls: list[str]) -> None:
        self.urls = urls
        self.fail = False

    def supports_extract(self) -> bool:
        return True

    async def extract(self, urls: list[str], *, format: str | None = None) -> list[dict]:
        assert urls == self.urls
        assert format == "markdown"
        if self.fail:
            raise RuntimeError(f"failed while fetching {self.urls[0]}")
        return [
            {
                "url": urls[0],
                "title": "Long",
                "raw_content": "x" * 3000,
                "error": None,
            },
            {
                "url": urls[1],
                "title": "Short",
                "raw_content": "short result",
                "error": None,
            },
        ]


def main() -> None:
    patched_root = Path(sys.argv[1]).resolve()
    assert (patched_root / "tools/url_safety.py").is_file()
    assert (patched_root / "tools/web_tools.py").is_file()

    from agent import web_search_registry
    from tools import url_safety, web_tools

    assert Path(url_safety.__file__).resolve().is_relative_to(patched_root)
    assert Path(web_tools.__file__).resolve().is_relative_to(patched_root)

    urls = [
        "https://example.test/private/path?topic=confidential-alpha",
        "https://example.test/other?topic=confidential-beta",
    ]
    provider = Provider(urls)
    debug = DebugRecorder()
    logs = LogRecorder()

    async def safe_url(_url: str) -> bool:
        return True

    web_tools.async_is_safe_url = safe_url
    web_tools._ensure_web_plugins_loaded = lambda: None
    web_tools._get_extract_backend = lambda: provider.name
    web_tools._rescue_eligible = lambda _provider: False
    web_tools._store_full_text = lambda _url, _content: "/redacted/full-text.md"
    web_tools._debug = debug
    web_search_registry.get_provider = lambda name: provider if name == provider.name else None
    web_search_registry.get_active_extract_provider = lambda: provider
    web_search_registry._disabled_web_plugin_for = lambda **_kwargs: None

    web_tools.logger.handlers = [logs]
    web_tools.logger.propagate = False
    web_tools.logger.setLevel(logging.DEBUG)

    result = json.loads(
        asyncio.run(web_tools.web_extract_tool(urls, format="markdown", char_limit=2000))
    )
    assert [entry["url"] for entry in result["results"]] == urls
    assert len(debug.calls) == 1
    debug_payload = debug.calls[0][1]
    assert debug_payload["parameters"] == {
        "url_count": 2,
        "format": "markdown",
        "char_limit": 2000,
    }
    assert debug_payload["truncation_metrics"][0]["result_index"] == 0
    assert "url" not in debug_payload["truncation_metrics"][0]

    diagnostics = "\n".join(logs.messages) + "\n" + json.dumps(debug.calls)
    for url in urls:
        assert url not in diagnostics
    assert "confidential-alpha" not in diagnostics
    assert "confidential-beta" not in diagnostics
    assert any("web_extract result 1" in message for message in logs.messages)

    logs.messages.clear()
    debug.calls.clear()
    provider.fail = True
    provider.urls = [urls[0]]
    failed = json.loads(asyncio.run(web_tools.web_extract_tool([urls[0]], format="markdown")))
    assert failed == {"error": "Web extraction failed"}
    diagnostics = "\n".join(logs.messages) + "\n" + json.dumps(debug.calls)
    assert urls[0] not in diagnostics
    assert "confidential-alpha" not in diagnostics
    assert "RuntimeError" in diagnostics

    safety_logs = LogRecorder()
    safety_url = "https://safety-target.example.test/private/path?topic=safety-secret"
    safety_host = "safety-target.example.test"
    private_ip = "10.23.45.67"
    exception_data = "dns-exception-confidential"

    url_safety.logger.handlers = [safety_logs]
    url_safety.logger.propagate = False
    url_safety.logger.setLevel(logging.DEBUG)
    url_safety._global_allow_private_urls = lambda: False

    def private_dns(*_args, **_kwargs):
        return [
            (
                url_safety.socket.AF_INET,
                url_safety.socket.SOCK_STREAM,
                0,
                "",
                (private_ip, 443),
            )
        ]

    url_safety.socket.getaddrinfo = private_dns
    assert not asyncio.run(url_safety.async_is_safe_url(safety_url))

    def failing_dns(*_args, **_kwargs):
        raise RuntimeError(f"{exception_data}: {safety_url} via {private_ip}")

    url_safety.socket.getaddrinfo = failing_dns
    assert not asyncio.run(url_safety.async_is_safe_url(safety_url))

    safety_diagnostics = "\n".join(safety_logs.messages)
    assert safety_url not in safety_diagnostics
    assert safety_host not in safety_diagnostics
    assert "/private/path" not in safety_diagnostics
    assert "topic=safety-secret" not in safety_diagnostics
    assert private_ip not in safety_diagnostics
    assert exception_data not in safety_diagnostics
    assert "Blocked request to private/internal address" in safety_diagnostics
    assert "RuntimeError" in safety_diagnostics


if __name__ == "__main__":
    main()
