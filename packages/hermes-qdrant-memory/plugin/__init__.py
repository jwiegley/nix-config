"""Qdrant memory provider plugin entry point."""

from .src.qdrant import QdrantMemoryProvider


def register(ctx) -> None:
    """Register the provider with Hermes."""
    ctx.register_memory_provider(QdrantMemoryProvider())


__all__ = ["QdrantMemoryProvider", "register"]
