"""Local web extraction plugin, with no hosted extraction service."""

from __future__ import annotations

from .provider import LocalWebExtractProvider


def register(ctx) -> None:
    """Register the local extraction provider with Hermes."""
    ctx.register_web_search_provider(LocalWebExtractProvider())
