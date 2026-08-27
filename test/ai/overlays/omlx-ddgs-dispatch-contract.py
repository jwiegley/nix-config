import asyncio
from types import SimpleNamespace

from ddgs.ddgs import DDGS
from omlx import websearch

calls: list[tuple[int | None, str, int, str]] = []
original_text = DDGS.text


def offline_text(
    provider: DDGS,
    query: str,
    *,
    max_results: int,
    backend: str,
) -> list[dict[str, str]]:
    calls.append((provider._timeout, query, max_results, backend))
    return [
        {
            "title": "Offline result",
            "href": "https://example.invalid/result",
            "body": "No network used",
        }
    ]


DDGS.text = offline_text
try:
    payload = asyncio.run(
        websearch.run_web_search(
            "offline dispatch",
            SimpleNamespace(
                web_search_provider="ddgs",
                web_search_brave_api_key="",
                web_search_searxng_url="",
                web_search_ddgs_backends="",
                web_search_max_results=1,
                web_search_content_mode="snippet",
                web_search_content_max_chars=1000,
                web_search_content_truncate=True,
            ),
        )
    )
finally:
    DDGS.text = original_text

expected_calls = [(int(websearch.HTTP_TIMEOUT_SECONDS), "offline dispatch", 1, "auto")]
if calls != expected_calls:
    raise SystemExit(f"oMLX DDGS dispatch mismatch: expected {expected_calls}, got {calls}")
expected_payload = {
    "ok": True,
    "provider": "ddgs",
    "results": [
        {
            "title": "Offline result",
            "url": "https://example.invalid/result",
            "snippet": "No network used",
        }
    ],
}
if payload != expected_payload:
    raise SystemExit(
        f"oMLX DDGS result mapping mismatch: expected {expected_payload}, got {payload}"
    )
