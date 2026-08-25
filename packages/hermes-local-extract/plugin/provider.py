"""Local web extraction — Hermes web provider plugin.

Implements the EXTRACT half of Hermes' web capability without an intermediary
extraction service: SearXNG (self-hosted) does search, and this provider fetches
the requested page itself and renders it to Markdown with trafilatura. The
requested origin still receives its normal HTTP request. This replaces an
earlier hosted r.jina.ai backend, which also received every extracted URL and
its content.

Why trafilatura, and why in a SUBPROCESS:

  * Quality. Best-in-class boilerplate rejection among non-browser extractors
    (ScrapingHub article-extraction-benchmark F1 0.945 vs readability-lxml's
    0.922), and markedly better than the hosted Jina Reader it replaces
    (~0.86 vs ~0.64 by published comparison, at roughly half the character
    count -- which is context-window budget).
  * No browser. Crawl4AI and self-hosted Jina Reader both require a headless
    Chromium per extraction. Article extraction does not need that extra
    service, mutable browser profile, or process lifecycle.
  * Subprocess, not an import. hermes-agent SEALS its venv and its build fails
    when anything in extraPythonPackages collides by name with a sealed
    package. trafilatura's closure carries certifi, urllib3 and
    charset-normalizer, and all three are already in that venv, so importing it
    into the agent is not merely inadvisable -- it does not build. The worker
    therefore lives in its own Nix python environment and this module speaks to
    it over JSON, using nothing but the standard library.

Config keys this provider responds to::

    web:
      extract_backend: "local"     # explicit per-capability
      backend: "local"             # shared fallback
"""

from __future__ import annotations

import json
import logging
import os
import re
import subprocess
from typing import Any, Dict, List

from agent.web_search_provider import WebSearchProvider
from tools.interrupt import is_interrupted

logger = logging.getLogger(__name__)

# Substituted at build time by the Nix package. Falls back to the env var so the
# plugin stays testable outside Nix.
WORKER = os.environ.get("HERMES_LOCAL_EXTRACT_WORKER", "@worker@")

# Curl transfers and redirect processing share one 20-second per-URL budget.
# Synchronous DNS can outlive that inner deadline, so the 230-second subprocess
# timeout is the hard outer bound on the whole batch.
BATCH_TIMEOUT_SECONDS = 230

# Keep a batch within the worker's sequential budget.
MAX_URLS = 10

# Anything scheme-like is scrubbed out of a reason before it is logged. The
# worker emits only stable failure classes, but this remains a defense against
# malformed or future worker output containing a research target URL.
_URL_RE = re.compile(r"[a-zA-Z][a-zA-Z0-9+.\-]*://\S+")

# A single reason must not be able to dominate the line -- an exception string
# can be arbitrarily long -- and neither must the set of them.
_MAX_REASON_CHARS = 120
_MAX_REASONS = 5
_STABLE_FAILURE_PREFIXES = (
    "only http/https URLs can be extracted",
    "URL contains a forbidden control character",
    "URL credentials are not accepted",
    "URL has no host",
    "URL has an invalid port",
    "could not resolve host",
    "refusing to fetch a non-public address",
    "host resolved to no usable address",
    "fetch failed",
    "extraction failed",
    "unexpected extraction error",
    "no article content could be extracted",
    "local extraction timed out",
    "local extractor process failed",
    "could not parse local extractor output",
    "Skipped: extract is capped",
)


def _stable_failure_reason(value: Any) -> str:
    text = " ".join(str(value).split())
    for prefix in _STABLE_FAILURE_PREFIXES:
        if text.startswith(prefix):
            return prefix
    return "local extraction failed"


def _failure_summary(results: List[Dict[str, Any]]) -> str:
    """Distinct failure reasons, URL-scrubbed, most frequent first.

    Empty string when nothing failed, which is what lets the caller keep the
    original single-clause log line for the common all-succeeded case.
    """
    counts: Dict[str, int] = {}
    for r in results:
        if not isinstance(r, dict) or not r.get("error"):
            continue
        # Collapse whitespace: the worker's longest reason is a wrapped
        # multi-line string, and a newline inside a log line would split one
        # record into two as far as any line-oriented reader is concerned.
        reason = _stable_failure_reason(_URL_RE.sub("<url>", str(r["error"])))
        if len(reason) > _MAX_REASON_CHARS:
            reason = reason[: _MAX_REASON_CHARS - 3] + "..."
        counts[reason] = counts.get(reason, 0) + 1

    # Frequency first, then alphabetical, so the line is stable across runs
    # with the same failures and diffable by eye.
    ordered = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    shown = [f"{reason} (x{n})" if n > 1 else reason for reason, n in ordered[:_MAX_REASONS]]
    if len(ordered) > _MAX_REASONS:
        shown.append(f"+{len(ordered) - _MAX_REASONS} more")
    return "; ".join(shown)


def _parse_worker_output(stdout: str, expected_urls: List[str]) -> List[Dict[str, Any]]:
    """Validate the worker's one-row-per-input, same-order JSON protocol."""
    results = json.loads(stdout)
    if not isinstance(results, list) or len(results) != len(expected_urls):
        raise ValueError("worker result count mismatch")

    required = {"url", "title", "content"}
    for expected_url, result in zip(expected_urls, results):
        if not isinstance(result, dict):
            raise TypeError("worker result is not an object")
        if set(result) not in (required, required | {"error"}):
            raise TypeError("worker result has invalid fields")
        if any(not isinstance(result[key], str) for key in required):
            raise TypeError("worker result fields are not strings")
        if result["url"] != expected_url:
            raise ValueError("worker result order mismatch")
        if "error" in result and not isinstance(result["error"], str):
            raise TypeError("worker error is not a string")
    return results


class LocalWebExtractProvider(WebSearchProvider):
    """Fetch and extract page content locally, with no external service."""

    @property
    def name(self) -> str:
        return "local"

    @property
    def display_name(self) -> str:
        return "Local extraction (trafilatura)"

    def is_available(self) -> bool:
        """True when the worker exists and is executable.

        A real check, not a constant: if the Nix substitution failed or the
        store path was garbage-collected, reporting True would make every
        extraction fail with a confusing subprocess error instead of a clear
        "backend unavailable".
        """
        return bool(WORKER) and os.access(WORKER, os.X_OK)

    def supports_search(self) -> bool:
        """False -- SearXNG owns search on this host. This provider only reads
        a URL it is handed; it has no index of its own."""
        return False

    def supports_extract(self) -> bool:
        return True

    def extract(self, urls: List[str], **kwargs: Any) -> List[Dict[str, Any]]:
        """Extract page content locally. Returns one item per input URL."""
        if not urls:
            return []

        if is_interrupted():
            return [{"url": u, "title": "", "content": "", "error": "Interrupted"} for u in urls]

        if not self.is_available():
            return [
                {"url": u, "title": "", "content": "",
                 "error": f"local extraction worker is missing or not executable: {WORKER}"}
                for u in urls
            ]

        accepted, rejected = list(urls[:MAX_URLS]), list(urls[MAX_URLS:])

        try:
            proc = subprocess.run(
                [WORKER],
                input=json.dumps({"urls": accepted}),
                capture_output=True,
                text=True,
                timeout=BATCH_TIMEOUT_SECONDS,
                check=False,
                # The worker needs no ambient environment and must not inherit
                # the agent's -- it carries API keys the extractor has no use
                # for. PATH is kept minimal for the interpreter's own needs.
                env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                     "HOME": os.environ.get("HOME", "/tmp")},
            )
        except subprocess.TimeoutExpired:
            # The only failure path that used to return in total silence -- no
            # count line, no warning -- which made a whole batch exceeding the
            # outer bound the single most severe outcome AND the least visible
            # one. Its two sibling handlers below both log; this now matches.
            logger.warning(
                "local-extract: worker timed out after %ss for %d URL(s)",
                BATCH_TIMEOUT_SECONDS,
                len(accepted),
            )
            return [
                {"url": u, "title": "", "content": "",
                 "error": f"local extraction timed out after {BATCH_TIMEOUT_SECONDS}s"}
                for u in accepted
            ] + [self._skipped(u) for u in rejected]
        except Exception as exc:  # noqa: BLE001
            logger.warning(
                "local-extract: worker invocation failed (%s)", type(exc).__name__
            )
            return [
                {"url": u, "title": "", "content": "", "error": "local extractor process failed"}
                for u in accepted
            ] + [self._skipped(u) for u in rejected]

        if proc.returncode != 0:
            logger.warning("local-extract: worker exited %s", proc.returncode)
            return [
                {"url": u, "title": "", "content": "", "error": "local extractor process failed"}
                for u in accepted
            ] + [self._skipped(u) for u in rejected]

        try:
            results = _parse_worker_output(proc.stdout, accepted)
        except Exception as exc:  # noqa: BLE001
            logger.warning(
                "local-extract: could not parse worker output (%s)", type(exc).__name__
            )
            return [
                {"url": u, "title": "", "content": "",
                 "error": "could not parse local extractor output"}
                for u in accepted
            ] + [self._skipped(u) for u in rejected]

        results.extend(self._skipped(u) for u in rejected)
        ok = sum(1 for r in results if isinstance(r, dict) and not r.get("error"))

        # The count alone is not actionable. A partial batch is NORMAL here --
        # measured across all four agent-log rotations (2026-08-04 onward),
        # 121 of 157 URLs extracted, with 12 of 105 batches returning nothing --
        # and every one of those was a page trafilatura could not render, not a
        # broken extractor: worker-level errors over the same period were zero.
        # Without the reason the two are indistinguishable in the log, which is
        # what made HermesExtractFailing an alert nobody could act on. The
        # reasons already exist in `results`; they were simply being discarded.
        #
        # The prefix through "succeeded" is load-bearing: hermes-health-check
        # matches EXTRACT_RESULT_RE against this line with re.search, so the
        # clause is appended rather than woven in.
        failures = _failure_summary(results)
        if failures:
            logger.info(
                "Local extract: %d/%d URL(s) succeeded; reasons: %s", ok, len(results), failures
            )
        else:
            logger.info("Local extract: %d/%d URL(s) succeeded", ok, len(results))
        return results

    @staticmethod
    def _skipped(url: str) -> Dict[str, Any]:
        return {"url": url, "title": "", "content": "",
                "error": f"Skipped: extract is capped at {MAX_URLS} URLs per call"}

    def get_setup_schema(self) -> Dict[str, Any]:
        return {
            "name": "Local extraction",
            "badge": "free · direct fetch · no API key",
            "tag": (
                "Fetches and extracts pages on this host with trafilatura. "
                "No intermediary extraction service receives the URL or content; "
                "the requested origin receives the normal HTTP request. "
                "Cannot render JavaScript-only pages."
            ),
            "env_vars": [],
        }
