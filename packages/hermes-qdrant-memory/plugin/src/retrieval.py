from typing import Any, Dict, List

from .store import _record_to_row, build_filter


def _limit(value: Any, default: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return default
    return max(1, min(parsed, 50))


def recall(
    store,
    query: str,
    *,
    mode: str = "vector",
    kind: str = "fact",
    category: str = "",
    workspace: str = "",
    user_id: str = "",
    limit: int = 10,
) -> List[Dict[str, Any]]:
    """Return ranked memory rows from Qdrant."""
    query = (query or "").strip()
    if not query:
        return []
    mode = mode if mode in {"hybrid", "vector"} else "vector"
    kind = kind if kind in {"fact", "turn", "any"} else "fact"
    limit = _limit(limit, 10)

    filter_obj = build_filter(workspace=workspace, user_id=user_id, kind=kind, category=category)
    dense_vec = store.embedder.embed_one(query)

    if mode == "vector":
        with store.io_guard():
            result = store.client.query_points(
                collection_name=store.collection,
                query=dense_vec,
                using="dense",
                query_filter=filter_obj,
                limit=limit,
                with_payload=True,
            )
        return [_record_to_row(r) for r in result.points]

    # hybrid: dense ANN + sparse BM25-like legs, fused via Qdrant's built-in RRF.
    # Filter goes on each Prefetch (pre-fusion) so workspace isolation is enforced
    # before candidates merge, not after.
    from .qdrant_rest import Fusion, FusionQuery, Prefetch, SparseVector

    sparse_indices, sparse_values = store.embedder.embed_sparse(query)
    fetch_k = limit * 3
    with store.io_guard():
        result = store.client.query_points(
            collection_name=store.collection,
            prefetch=[
                Prefetch(query=dense_vec, using="dense", limit=fetch_k, filter=filter_obj),
                Prefetch(
                    query=SparseVector(indices=sparse_indices, values=sparse_values),
                    using="sparse",
                    limit=fetch_k,
                    filter=filter_obj,
                ),
            ],
            query=FusionQuery(fusion=Fusion.RRF),
            limit=limit,
            with_payload=True,
        )
    return [_record_to_row(r) for r in result.points]


def format_prefetch(rows: list[dict[str, Any]], *, max_items: int = 5) -> str:
    if not rows:
        return ""
    lines = ["## Qdrant Memory"]
    for row in rows[:max_items]:
        content = row.get("abstract") or row.get("content") or ""
        content = " ".join(str(content).split())
        if len(content) > 500:
            content = content[:497] + "..."
        category = row.get("category") or row.get("kind") or "memory"
        row_id = row.get("id_str") or row.get("id")
        lines.append(f"- ({category}, id={row_id}) {content}")
    return "\n".join(lines)
