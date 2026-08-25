#!/usr/bin/env python3
"""Local URL -> Markdown extraction worker (trafilatura).

Runs in its OWN Nix python environment, spawned as a subprocess by the Hermes
plugin. It is deliberately NOT importable from the agent: hermes-agent seals its
venv and its build FAILS if anything in extraPythonPackages collides by name
with a sealed package, and trafilatura's closure carries certifi, urllib3 and
charset-normalizer -- all three of which are already in that venv. Subprocess
isolation sidesteps the collision entirely and mirrors how this host already
runs its MCP servers (lightPython / financialPython).

Protocol: read {"urls": [...]} as JSON on stdin, write a JSON list on stdout,
one object per URL in the SAME order, each {url, title, content, error?}.
Never writes anything but JSON to stdout; diagnostics go to stderr.
"""

from __future__ import annotations

import html as html_module
import ipaddress
import json
import math
import re
import resource
import socket
import subprocess
import sys
import tempfile
import time
from typing import Any, Dict, List
from urllib.parse import urljoin, urlparse

import trafilatura
from trafilatura.settings import DEFAULT_CONFIG

# Bound a single extraction. The host is memory-constrained and one runaway
# page must not stall an agent turn. Measured on this host: 0.02s for a 20KiB
# blog post, 1.71s for a 110KiB docs page -- 20s is generous.
DOWNLOAD_TIMEOUT = "20"
MAX_FILE_SIZE = "20000000"  # 20 MB of HTML

# Cap what reaches the model. Extraction is normally small (Wikipedia's Markdown
# article came out at 30KiB) but a pathological page should not silently consume
# the context window. Truncation is REPORTED in-band, never silent.
MAX_CONTENT_CHARS = 200_000
MAX_FILE_BYTES = 20_000_000
MAX_REDIRECTS = 5
CURL = "@curl@"


def _config() -> Any:
    from copy import deepcopy

    cfg = deepcopy(DEFAULT_CONFIG)
    cfg["DEFAULT"]["DOWNLOAD_TIMEOUT"] = DOWNLOAD_TIMEOUT
    cfg["DEFAULT"]["MAX_FILE_SIZE"] = MAX_FILE_SIZE
    return cfg


CONFIG = _config()


class UnsafeUrl(ValueError):
    """A URL that cannot be fetched without crossing the public-network boundary."""


def _validated_target(url: str):
    """Return the parsed URL and every resolved public address.

    Moving extraction in-house REINTRODUCES a risk the hosted service did not
    have: Jina fetched from its own infrastructure and structurally could not
    reach this network, whereas this worker runs directly on Hera with the
    user's network access. Without this check, an agent talked into extracting
    a private URL would proxy an internal service straight into a chat reply.

    Every resolved address is checked, not just the first. Connections are then
    pinned to one of these exact addresses, so DNS cannot change between this
    decision and the socket opened by curl.
    """
    if any(character in url for character in ("\0", "\r", "\n")):
        raise UnsafeUrl("URL contains a forbidden control character")
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise UnsafeUrl(
            f"only http/https URLs can be extracted (got {parsed.scheme or 'no scheme'})"
        )
    if parsed.username is not None or parsed.password is not None:
        raise UnsafeUrl("URL credentials are not accepted")
    host = parsed.hostname
    if not host:
        raise UnsafeUrl("URL has no host")

    try:
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
    except ValueError as exc:
        raise UnsafeUrl("URL has an invalid port") from exc

    try:
        infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
    except OSError as exc:
        raise UnsafeUrl("could not resolve host") from exc

    addresses: list[str] = []
    for info in infos:
        addr = ipaddress.ip_address(info[4][0])
        if (
            not addr.is_global
            or addr.is_multicast
            or (isinstance(addr, ipaddress.IPv6Address) and addr.is_site_local)
        ):
            # Deliberately does NOT echo the resolved address back to the
            # caller -- that would turn this guard into an internal-network
            # scanner with a helpful readout.
            raise UnsafeUrl("refusing to fetch a non-public address")
        rendered = str(addr)
        if rendered not in addresses:
            addresses.append(rendered)
    if not addresses:
        raise UnsafeUrl("host resolved to no usable address")
    return parsed, addresses


def ssrf_reject_reason(url: str) -> str | None:
    """Return a rejection reason, or None if the URL is safe to fetch."""
    try:
        _validated_target(url)
    except UnsafeUrl as exc:
        return str(exc)
    return None


def _curl_config_value(value: str) -> str:
    """Quote one value for curl's stdin configuration format."""
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _header_value(headers: str, name: str) -> str:
    """Read one header from the last response block without logging its value."""
    blocks = re.split(r"\r?\n\r?\n", headers.strip())
    for line in reversed(blocks[-1].splitlines() if blocks else []):
        key, separator, value = line.partition(":")
        if separator and key.strip().lower() == name.lower():
            return value.strip()
    return ""


def _limit_output_file_size() -> None:
    """Keep curl from writing an oversized decompressed response."""
    _soft, hard = resource.getrlimit(resource.RLIMIT_FSIZE)
    limit = MAX_FILE_BYTES if hard == resource.RLIM_INFINITY else min(MAX_FILE_BYTES, hard)
    resource.setrlimit(resource.RLIMIT_FSIZE, (limit, limit))


def _curl_once(
    url: str,
    parsed,
    address: str,
    *,
    timeout_seconds: float | None = None,
) -> tuple[int, str, bytes]:
    """Fetch exactly one response through a previously validated address."""
    curl_timeout = max(
        1,
        min(
            int(DOWNLOAD_TIMEOUT),
            math.ceil(timeout_seconds if timeout_seconds is not None else int(DOWNLOAD_TIMEOUT)),
        ),
    )
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    resolved_address = f"[{address}]" if ":" in address else address
    resolve = f"{parsed.hostname}:{port}:{resolved_address}"
    with tempfile.TemporaryDirectory(prefix="hermes-local-extract-") as directory:
        header_path = f"{directory}/headers"
        body_path = f"{directory}/body"
        process = subprocess.run(
            [
                CURL,
                "--disable",
                "--silent",
                "--show-error",
                "--compressed",
                "--noproxy",
                "*",
                "--proxy",
                "",
                "--proto",
                "=http,https",
                "--connect-timeout",
                str(min(10, curl_timeout)),
                "--max-time",
                str(curl_timeout),
                "--max-filesize",
                str(MAX_FILE_BYTES),
                "--max-redirs",
                "0",
                "--resolve",
                resolve,
                "--dump-header",
                header_path,
                "--output",
                body_path,
                "--write-out",
                "%{http_code}",
                "--config",
                "-",
            ],
            input=f"url = {_curl_config_value(url)}\n",
            capture_output=True,
            text=True,
            timeout=curl_timeout + 1,
            check=False,
            env={"PATH": "/usr/bin:/bin"},
            preexec_fn=_limit_output_file_size,
        )
        if process.returncode != 0 or not re.fullmatch(r"[0-9]{3}", process.stdout):
            raise RuntimeError("curl could not fetch the validated public URL")
        with open(header_path, encoding="iso-8859-1") as handle:
            headers = handle.read(64 * 1024 + 1)
        if len(headers) > 64 * 1024:
            raise RuntimeError("response headers exceeded the 64 KiB limit")
        with open(body_path, "rb") as handle:
            body = handle.read(MAX_FILE_BYTES + 1)
        if len(body) > MAX_FILE_BYTES:
            raise RuntimeError("response body exceeded the 20 MB limit")
        return int(process.stdout), headers, body


def _decode_body(body: bytes, headers: str) -> str:
    content_type = _header_value(headers, "content-type")
    match = re.search(r"charset=([^;\s]+)", content_type, re.IGNORECASE)
    encoding = match.group(1).strip('"\'') if match else "utf-8"
    try:
        return body.decode(encoding, errors="replace")
    except LookupError:
        return body.decode("utf-8", errors="replace")


def _fetch_public_url(url: str) -> str:
    """Fetch a public URL with one curl/redirect budget after resolution.

    Python's synchronous resolver cannot be interrupted at this deadline. The
    parent worker's outer timeout remains the hard bound if DNS itself stalls.
    """
    current = url
    deadline = time.monotonic() + int(DOWNLOAD_TIMEOUT)
    for redirect_count in range(MAX_REDIRECTS + 1):
        parsed, addresses = _validated_target(current)
        last_error: Exception | None = None
        response = None
        for address in addresses:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("public URL fetch exceeded its total time budget")
            try:
                response = _curl_once(
                    current,
                    parsed,
                    address,
                    timeout_seconds=remaining,
                )
                break
            except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
                last_error = exc
        if response is None:
            raise RuntimeError("fetch failed for every validated public address") from last_error

        status, headers, body = response
        if status in (301, 302, 303, 307, 308):
            location = _header_value(headers, "location")
            if not location:
                raise RuntimeError("redirect response omitted Location")
            if redirect_count >= MAX_REDIRECTS:
                raise RuntimeError("redirect limit exceeded")
            current = urljoin(current, location)
            continue
        if not 200 <= status < 300:
            raise RuntimeError(f"public URL returned HTTP {status}")
        return _decode_body(body, headers)
    raise RuntimeError("redirect limit exceeded")


_TITLE_RE = re.compile(r"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)


def _best_title(html: str, url: str) -> str:
    """Prefer the authored <title>, falling back to trafilatura's metadata.

    Order matters and is deliberate. trafilatura's metadata title is a DOM
    HEURISTIC -- it picks a heading it believes is the title -- and it can pick
    chrome. Observed on nixos.org's Nix manual: it returned "Keyboard
    shortcuts" (a UI legend near the top of the page) while the authored
    <title> was "Introduction - Nix 2.34.9 Reference Manual". Handing the agent
    a title of "Keyboard shortcuts" for a page about the Nix language is worse
    than useless -- it is confidently wrong, and the agent will repeat it.

    <title> is authored metadata rather than a guess, so it is the primary. The
    heuristic stays as the fallback for pages that omit <title> entirely.
    """
    match = _TITLE_RE.search(html or "")
    if match:
        # Collapse the whitespace/newlines that pretty-printed HTML leaves in
        # multi-line <title> elements.
        candidate = html_module.unescape(" ".join(match.group(1).split())).strip()
        if candidate:
            return candidate[:300]

    try:
        meta = trafilatura.extract_metadata(html, default_url=url)
        if meta is not None and getattr(meta, "title", None):
            return str(meta.title)[:300]
    except Exception:  # noqa: BLE001
        pass  # a missing title never fails an otherwise good extraction
    return ""


def extract_one(url: str) -> Dict[str, Any]:
    try:
        downloaded = _fetch_public_url(url)
    except UnsafeUrl as exc:
        return {"url": url, "title": "", "content": "", "error": str(exc)}
    except Exception:  # noqa: BLE001
        return {"url": url, "title": "", "content": "", "error": "fetch failed"}

    try:
        content = trafilatura.extract(
            downloaded,
            url=url,
            output_format="markdown",  # native; no HTML->MD converter needed
            include_links=True,
            include_tables=True,
            include_comments=False,  # comment threads are context-window noise
            favor_precision=True,  # bias against boilerplate leaking through
            deduplicate=True,
            config=CONFIG,
        )
    except Exception:  # noqa: BLE001
        return {"url": url, "title": "", "content": "", "error": "extraction failed"}

    title = _best_title(downloaded, url)

    if not content:
        # trafilatura returns None rather than emitting surrounding chrome, so
        # an empty result must be reported as an ERROR: an empty success would
        # read to the agent as "this page is blank", which is a different and
        # wrong conclusion.
        #
        # State BOTH plausible causes and commit to neither. There are two, and
        # they are indistinguishable from here: a JavaScript-only shell, or a
        # page that simply is not prose. trafilatura is tuned for articles and
        # scores poorly on index/listing pages (~0.52 on collection pages in
        # WCXB) -- blog.rust-lang.org's post index returns nothing for exactly
        # that reason, with no JavaScript involved. Naming only the JS cause
        # would hand the agent a confident misdiagnosis to repeat to the user.
        return {"url": url, "title": title, "content": "",
                "error": ("no article content could be extracted. The page is either "
                          "JavaScript-rendered (this extractor runs no browser) or is a "
                          "link index / listing rather than prose. If it is a listing, "
                          "try extracting one of the linked pages instead")}

    if len(content) > MAX_CONTENT_CHARS:
        content = content[:MAX_CONTENT_CHARS] + "\n\n[truncated by local extractor]"

    return {"url": url, "title": title, "content": content}


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        urls = payload["urls"]
        if not isinstance(urls, list):
            raise TypeError("urls must be a list")
    except Exception as exc:  # noqa: BLE001
        print(json.dumps({"error": f"bad request: {exc}"}), file=sys.stdout)
        return 2

    results: List[Dict[str, Any]] = []
    for url in urls:
        try:
            results.append(extract_one(str(url)))
        except Exception:  # noqa: BLE001
            # One bad URL must never lose the other results in the batch.
            results.append({"url": str(url), "title": "", "content": "",
                            "error": "unexpected extraction error"})

    json.dump(results, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
