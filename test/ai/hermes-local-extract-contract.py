#!/usr/bin/env python3
"""Behavioral contract for the Hermes local extraction plugin."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import socket
import subprocess
import sys
import tempfile
import types
from pathlib import Path


def load_module(name: str, path: Path, *, package: bool = False):
    if path.suffix == ".py":
        spec = importlib.util.spec_from_file_location(
            name,
            path,
            submodule_search_locations=[str(path.parent)] if package else None,
        )
    else:
        loader = importlib.machinery.SourceFileLoader(name, str(path))
        spec = importlib.util.spec_from_loader(name, loader)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def main() -> None:
    root = Path(sys.argv[1]).resolve()
    worker = load_module("hermes_local_extract_worker", root / "libexec/hermes-local-extract-worker")
    assert "trafilatura.fetch_url" not in (root / "libexec/hermes-local-extract-worker").read_text()

    original_getaddrinfo = worker.socket.getaddrinfo
    worker.socket.getaddrinfo = lambda *_args, **_kwargs: [
        (socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", ("127.0.0.1", 80))
    ]
    assert "non-public" in worker.ssrf_reject_reason("http://example.test/")
    worker.socket.getaddrinfo = lambda *_args, **_kwargs: [
        (socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", ("8.8.8.8", 443))
    ]
    assert worker.ssrf_reject_reason("https://example.test/") is None
    for addresses in [
        ["8.8.8.8", "127.0.0.1"],
        ["127.0.0.1", "8.8.8.8"],
    ]:
        worker.socket.getaddrinfo = lambda *_args, _addresses=addresses, **_kwargs: [
            (socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", (address, 443))
            for address in _addresses
        ]
        assert "non-public" in worker.ssrf_reject_reason("https://example.test/")
    worker.socket.getaddrinfo = lambda *_args, **_kwargs: [
        (socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", ("100.64.0.1", 443))
    ]
    assert "non-public" in worker.ssrf_reject_reason("https://example.test/")
    for family, address in [
        (socket.AF_INET, "239.255.255.250"),
        (socket.AF_INET6, "ff02::1"),
        (socket.AF_INET6, "fec0::1"),
    ]:
        worker.socket.getaddrinfo = lambda *_args, _family=family, _address=address, **_kwargs: [
            (_family, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", (_address, 443))
        ]
        assert "non-public" in worker.ssrf_reject_reason("https://example.test/")
    worker.socket.getaddrinfo = original_getaddrinfo
    assert worker.ssrf_reject_reason("file:///etc/passwd") is not None
    assert worker.CONFIG["DEFAULT"]["DOWNLOAD_TIMEOUT"] == "20"
    assert worker.CONFIG["DEFAULT"]["MAX_FILE_SIZE"] == "20000000"
    assert worker.MAX_CONTENT_CHARS == 200_000

    # Exercise the installed worker executable itself. Non-network schemes
    # make this deterministic while still proving its exact one-row-per-input,
    # same-order protocol (including duplicate inputs).
    packaged_urls = ["file:///first", "file:///second", "file:///first"]
    packaged = subprocess.run(
        [str(root / "libexec/hermes-local-extract-worker")],
        input=json.dumps({"urls": packaged_urls}),
        capture_output=True,
        text=True,
        check=False,
    )
    assert packaged.returncode == 0
    packaged_rows = json.loads(packaged.stdout)
    assert [row["url"] for row in packaged_rows] == packaged_urls
    assert len(packaged_rows) == len(packaged_urls)
    assert all(
        set(row) == {"url", "title", "content", "error"}
        and all(isinstance(row[key], str) for key in row)
        for row in packaged_rows
    )

    original_fetch_public_url = worker._fetch_public_url
    worker._fetch_public_url = lambda _url: "<title> Example  Title </title>"
    worker.trafilatura.extract = lambda *_args, **_kwargs: "x" * (worker.MAX_CONTENT_CHARS + 1)
    extracted = worker.extract_one("https://example.test/article")
    worker._fetch_public_url = original_fetch_public_url
    assert extracted["title"] == "Example Title"
    assert len(extracted["content"]) > worker.MAX_CONTENT_CHARS
    assert extracted["content"].endswith("[truncated by local extractor]")

    # The actual curl seam must pin the validated address, refuse automatic
    # redirect following, and keep the URL out of process argv.
    curl_calls = []
    original_run = worker.subprocess.run

    def fake_curl(argv, **kwargs):
        curl_calls.append((argv, kwargs))
        header_path = Path(argv[argv.index("--dump-header") + 1])
        body_path = Path(argv[argv.index("--output") + 1])
        header_path.write_text("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n\r\n")
        body_path.write_bytes(b"<title>Pinned</title>")
        return subprocess.CompletedProcess(argv, 0, stdout="200", stderr="")

    worker.subprocess.run = fake_curl
    parsed = worker.urlparse("https://example.test/article?private=query")
    status, _headers, body = worker._curl_once(
        "https://example.test/article?private=query",
        parsed,
        "8.8.8.8",
        timeout_seconds=7.2,
    )
    worker.subprocess.run = original_run
    argv, kwargs = curl_calls[0]
    assert status == 200 and body == b"<title>Pinned</title>"
    assert argv[argv.index("--resolve") + 1] == "example.test:443:8.8.8.8"
    assert argv[argv.index("--max-redirs") + 1] == "0"
    assert argv[argv.index("--max-time") + 1] == "8"
    assert "--location" not in argv and "-L" not in argv
    assert not any("private=query" in argument for argument in argv)
    assert "private=query" in kwargs["input"]
    assert kwargs["preexec_fn"] is worker._limit_output_file_size

    # The real helper-process boundary must stop decompressed output growth;
    # curl's transfer-size option alone does not constrain its output file.
    original_max_file_bytes = worker.MAX_FILE_BYTES
    try:
        worker.MAX_FILE_BYTES = 4096
        with tempfile.TemporaryDirectory(prefix="hermes-local-extract-contract-") as directory:
            bounded_path = Path(directory) / "bounded-output-probe"
            bounded = subprocess.run(
                [
                    sys.executable,
                    "-c",
                    "import pathlib,sys; pathlib.Path(sys.argv[1]).write_bytes(b'x' * 65536)",
                    str(bounded_path),
                ],
                check=False,
                stderr=subprocess.DEVNULL,
                preexec_fn=worker._limit_output_file_size,
            )
            assert bounded.returncode != 0
            assert bounded_path.stat().st_size <= 4096
    finally:
        worker.MAX_FILE_BYTES = original_max_file_bytes

    # A redirect is followed only after its new hostname is resolved and
    # rejected. The private target must never reach the connection seam.
    redirect_calls = []
    original_getaddrinfo = worker.socket.getaddrinfo
    original_curl_once = worker._curl_once

    def redirect_resolution(host, *_args, **_kwargs):
        address = "8.8.8.8" if host == "public.example" else "127.0.0.1"
        return [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", (address, 443))]

    def redirect_once(url, parsed, address, *, timeout_seconds=None):
        redirect_calls.append((url, parsed.hostname, address))
        return 302, "HTTP/1.1 302 Found\r\nLocation: https://private.example/secret\r\n\r\n", b""

    worker.socket.getaddrinfo = redirect_resolution
    worker._curl_once = redirect_once
    try:
        worker._fetch_public_url("https://public.example/start")
    except worker.UnsafeUrl as exc:
        assert "non-public" in str(exc)
    else:
        raise AssertionError("private redirect target was not rejected")
    worker.socket.getaddrinfo = original_getaddrinfo
    worker._curl_once = original_curl_once
    assert redirect_calls == [
        ("https://public.example/start", "public.example", "8.8.8.8")
    ]

    # The 20-second budget belongs to the URL, not to each redirect hop. A
    # mutant that grants every hop a fresh DOWNLOAD_TIMEOUT reaches the third
    # response instead of stopping before another connection.
    budget_calls = []
    clock = iter([100.0, 100.0, 110.0, 121.0])

    def public_resolution(_host, *_args, **_kwargs):
        return [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", ("8.8.8.8", 443))]

    def budgeted_redirect(url, _parsed, _address, *, timeout_seconds=None):
        budget_calls.append((url, timeout_seconds))
        return 302, "HTTP/1.1 302 Found\r\nLocation: /next\r\n\r\n", b""

    original_monotonic = worker.time.monotonic
    worker.time.monotonic = lambda: next(clock)
    worker.socket.getaddrinfo = public_resolution
    worker._curl_once = budgeted_redirect
    try:
        worker._fetch_public_url("https://public.example/start")
    except TimeoutError:
        pass
    else:
        raise AssertionError("redirect hops received independent time budgets")
    worker.time.monotonic = original_monotonic
    worker.socket.getaddrinfo = original_getaddrinfo
    worker._curl_once = original_curl_once
    assert len(budget_calls) == 2
    assert budget_calls[0][1] == 20
    assert budget_calls[1][1] == 10

    agent = types.ModuleType("agent")
    agent.__path__ = []
    provider_base = types.ModuleType("agent.web_search_provider")

    class WebSearchProvider:
        pass

    provider_base.WebSearchProvider = WebSearchProvider
    sys.modules["agent"] = agent
    sys.modules["agent.web_search_provider"] = provider_base
    interrupt_state = {"requested": False}
    tools_package = types.ModuleType("tools")
    tools_package.__path__ = []
    interrupt_module = types.ModuleType("tools.interrupt")
    interrupt_module.is_interrupted = lambda: interrupt_state["requested"]
    sys.modules["tools"] = tools_package
    sys.modules["tools.interrupt"] = interrupt_module
    parent = types.ModuleType("hermes_plugins")
    parent.__path__ = []
    sys.modules["hermes_plugins"] = parent
    plugin = load_module(
        "hermes_plugins.nix-managed-hermes-local-extract",
        root / "__init__.py",
        package=True,
    )

    registered = []
    plugin.register(types.SimpleNamespace(register_web_search_provider=registered.append))
    assert len(registered) == 1
    provider = registered[0]
    assert provider.name == "local"
    assert provider.supports_search() is False
    assert provider.supports_extract() is True
    assert provider.is_available()

    provider_module = sys.modules[f"{plugin.__name__}.provider"]
    assert provider_module.is_interrupted is interrupt_module.is_interrupted
    assert "install_availability_shim" not in provider_module.__dict__
    assert "_is_backend_available" not in (root / "provider.py").read_text()

    captured = {}

    def fake_run(argv, **kwargs):
        captured["argv"] = argv
        captured.update(kwargs)
        urls = json.loads(kwargs["input"])["urls"]
        payload = [{"url": url, "title": "title", "content": "content"} for url in urls]
        return types.SimpleNamespace(returncode=0, stdout=json.dumps(payload), stderr="")

    provider_module.subprocess.run = fake_run
    os.environ["TEST_ONLY_SECRET"] = "must-not-reach-worker"
    urls = [f"https://example.test/{index}" for index in range(12)]
    results = provider.extract(urls)
    os.environ.pop("TEST_ONLY_SECRET", None)
    assert len(results) == 12
    assert len(json.loads(captured["input"])["urls"]) == 10
    assert set(captured["env"]) == {"HOME", "PATH"}
    assert captured["timeout"] == 230
    assert all("capped at 10" in item["error"] for item in results[10:])

    interrupt_state["requested"] = True
    interrupted = provider.extract(["https://example.test/interrupted"])
    interrupt_state["requested"] = False
    assert interrupted == [
        {
            "url": "https://example.test/interrupted",
            "title": "",
            "content": "",
            "error": "Interrupted",
        }
    ]

    protocol_urls = ["https://example.test/a", "https://example.test/b"]
    mixed_rows = [
        {
            "url": protocol_urls[0],
            "title": "A",
            "content": "first content",
        },
        {
            "url": protocol_urls[1],
            "title": "",
            "content": "",
            "error": "fetch failed",
        },
    ]
    provider_module.subprocess.run = lambda *_args, **_kwargs: types.SimpleNamespace(
        returncode=0,
        stdout=json.dumps(mixed_rows),
        stderr="",
    )
    assert provider.extract(protocol_urls) == mixed_rows

    malformed_outputs = [
        "{",
        json.dumps({"url": protocol_urls[0]}),
        json.dumps(mixed_rows[:1]),
        json.dumps([*mixed_rows, mixed_rows[0]]),
        json.dumps(list(reversed(mixed_rows))),
        json.dumps(["not-an-object", mixed_rows[1]]),
        json.dumps(
            [
                {"url": protocol_urls[0], "title": "A"},
                mixed_rows[1],
            ]
        ),
        json.dumps(
            [
                {**mixed_rows[0], "unexpected": "field"},
                mixed_rows[1],
            ]
        ),
        json.dumps(
            [
                {**mixed_rows[0], "url": 1},
                mixed_rows[1],
            ]
        ),
        json.dumps(
            [
                {**mixed_rows[0], "title": 1},
                mixed_rows[1],
            ]
        ),
        json.dumps(
            [
                {**mixed_rows[0], "content": 1},
                mixed_rows[1],
            ]
        ),
        json.dumps(
            [
                mixed_rows[0],
                {**mixed_rows[1], "error": 1},
            ]
        ),
    ]
    protocol_failure = [
        {
            "url": url,
            "title": "",
            "content": "",
            "error": "could not parse local extractor output",
        }
        for url in protocol_urls
    ]
    for stdout in malformed_outputs:
        provider_module.subprocess.run = (
            lambda *_args, _stdout=stdout, **_kwargs: types.SimpleNamespace(
                returncode=0,
                stdout=_stdout,
                stderr="",
            )
        )
        assert provider.extract(protocol_urls) == protocol_failure

    summary = provider_module._failure_summary(
        [
            {"error": "fetch failed: https://private.example/path?token=value"},
            {"error": "fetch failed: https://private.example/other"},
        ]
    )
    assert "private.example" not in summary
    assert summary == "fetch failed (x2)"

    provider_module.subprocess.run = lambda *_args, **_kwargs: types.SimpleNamespace(
        returncode=1,
        stdout="",
        stderr="secret-bearing worker diagnostic",
    )
    failed = provider.extract(["https://example.test/failure"])
    assert failed[0]["error"] == "local extractor process failed"
    assert "secret-bearing" not in json.dumps(failed)

if __name__ == "__main__":
    main()
