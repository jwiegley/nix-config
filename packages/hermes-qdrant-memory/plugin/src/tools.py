import json
from typing import Any, Dict

from tools.registry import tool_error


QDRANT_RECALL = {
    "name": "qdrant_recall",
    "description": (
        "Recall durable workspace memory from Qdrant. Uses vector search by default; "
        "hybrid (vector + sparse BM25-like, fused via RRF) also available. "
        "Returns memory IDs, snippets, scores, and provenance turn IDs."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "query": {"type": "string", "description": "What to search memory for."},
            "mode": {
                "type": "string",
                "enum": ["hybrid", "vector"],
                "description": "Search mode. Default vector; hybrid adds sparse BM25 fused via RRF.",
            },
            "kind": {
                "type": "string",
                "enum": ["fact", "turn", "any"],
                "description": "Which rows to return. Default fact; turn = raw conversation; any = both.",
            },
            "category": {
                "type": "string",
                "description": "Optional filter: preference, entity, event, case, pattern, or general.",
            },
            "limit": {"type": "integer", "description": "Max results (1-50, default from config)."},
        },
        "required": ["query"],
    },
}

QDRANT_REMEMBER = {
    "name": "qdrant_remember",
    "description": "Store a durable fact the user would expect Hermes to remember.",
    "parameters": {
        "type": "object",
        "properties": {
            "content": {
                "type": "string",
                "description": "The durable fact to store, one concise statement.",
            },
            "abstract": {"type": "string", "description": "Optional one-sentence summary."},
            "category": {
                "type": "string",
                "enum": ["preference", "entity", "event", "case", "pattern", "general"],
                "description": "Fact type. Defaults to general.",
            },
            "tags": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Optional short search tags.",
            },
        },
        "required": ["content"],
    },
}

QDRANT_READ = {
    "name": "qdrant_read",
    "description": (
        "Read one memory by ID (full content + metadata). For facts, optionally "
        "include the provenance turns it was extracted from."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "id": {"type": "string", "description": "Exact memory ID from a qdrant_recall result."},
            "include_provenance": {
                "type": "boolean",
                "description": "If true, also return the source turns for a fact.",
            },
        },
        "required": ["id"],
    },
}

QDRANT_FORGET = {
    "name": "qdrant_forget",
    "description": (
        "Preview or delete a memory. Preview candidates first when the user asks "
        "to forget something by description. Delete requires an exact ID."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "action": {
                "type": "string",
                "enum": ["preview", "delete"],
                "description": "preview = list candidates by description; delete = remove one exact ID.",
            },
            "query": {"type": "string", "description": "Required for preview: what to forget."},
            "id": {"type": "string", "description": "Required for delete: exact memory ID."},
            "limit": {
                "type": "integer",
                "description": "Preview only: max candidates (default 5).",
            },
        },
        "required": ["action"],
    },
}

TOOL_SCHEMAS = [QDRANT_RECALL, QDRANT_REMEMBER, QDRANT_READ, QDRANT_FORGET]


def _json(payload: Any) -> str:
    return json.dumps(payload, ensure_ascii=False, default=str)


def _clean_tags(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    out = []
    seen: set[str] = set()
    for item in value:
        tag = str(item).strip()
        if tag and tag not in seen:
            seen.add(tag)
            out.append(tag)
    return out


def _format_result(row: Dict[str, Any], *, include_full: bool = False) -> Dict[str, Any]:
    content = row.get("content") or ""
    snippet = " ".join(str(row.get("abstract") or content).split())
    if len(snippet) > 700 and not include_full:
        snippet = snippet[:697] + "..."
    row_id = row.get("id_str") or row.get("id")
    payload: Dict[str, Any] = {
        "id": row_id,
        "kind": row.get("kind"),
        "category": row.get("category") or "",
        "snippet": snippet,
        "tags": row.get("tags") or [],
        "provenance_turn_ids": row.get("provenance_turn_ids") or [],
        "created_at": row.get("created_at"),
    }
    for score_key in ("_relevance_score", "_distance", "_score"):
        if score_key in row:
            payload[score_key] = row[score_key]
    if include_full:
        payload["content"] = content
        payload["session_id"] = row.get("session_id") or ""
        payload["role"] = row.get("role") or ""
        payload["source"] = row.get("source") or ""
    return payload


class QdrantToolDispatcher:
    def __init__(self, provider) -> None:
        self.provider = provider

    def handle(self, tool_name: str, args: Dict[str, Any]) -> str:
        if tool_name == "qdrant_recall":
            return self._recall(args)
        if tool_name == "qdrant_remember":
            return self._remember(args)
        if tool_name == "qdrant_read":
            return self._read(args)
        if tool_name == "qdrant_forget":
            return self._forget(args)
        return tool_error(f"Unknown Qdrant memory tool: {tool_name}")

    def _recall(self, args: Dict[str, Any]) -> str:
        query = str(args.get("query") or "").strip()
        if not query:
            return tool_error("query is required")
        rows = self.provider.recall(
            query,
            mode=args.get("mode") or "",
            kind=args.get("kind") or "fact",
            category=args.get("category") or "",
            limit=(
                lim
                if (lim := args.get("limit")) is not None
                else self.provider.config["retrieval"]["top_k"]
            ),
        )
        return _json({"results": [_format_result(row) for row in rows], "total": len(rows)})

    def _remember(self, args: Dict[str, Any]) -> str:
        content = str(args.get("content") or "").strip()
        if not content:
            return tool_error("content is required")
        category = str(args.get("category") or "general").strip() or "general"
        row = self.provider.build_fact_row(
            content=content,
            abstract=str(args.get("abstract") or "").strip(),
            category=category,
            tags=_clean_tags(args.get("tags")),
            provenance_turn_ids=[],
            source="remember",
        )
        existing = self.provider.existing_fact(row)
        if existing:
            return _json(
                {
                    "status": "exists",
                    "id": existing.get("id_str") or existing.get("id"),
                    "content": existing.get("content"),
                }
            )
        self.provider.store.add_row(row)
        return _json({"status": "stored", "id": row["id"], "content": content})

    def _read(self, args: Dict[str, Any]) -> str:
        memory_id = str(args.get("id") or "").strip()
        if not memory_id:
            return tool_error("id is required")
        ws, uid = self.provider.workspace, self.provider.user_id
        row = self.provider.store.get_by_id(memory_id, workspace=ws, user_id=uid)
        if not row:
            return tool_error(f"memory not found: {memory_id}")
        payload: Dict[str, Any] = {"memory": _format_result(row, include_full=True)}
        if args.get("include_provenance"):
            payload["provenance"] = [
                _format_result(item, include_full=True)
                for item in self.provider.store.get_by_ids(
                    row.get("provenance_turn_ids") or [], workspace=ws, user_id=uid
                )
            ]
        return _json(payload)

    def _forget(self, args: Dict[str, Any]) -> str:
        action = str(args.get("action") or "").strip()
        if action == "preview":
            query = str(args.get("query") or "").strip()
            if not query:
                return tool_error("query is required for preview")
            rows = self.provider.recall(
                query,
                mode="hybrid",
                kind="fact",
                limit=(lim if (lim := args.get("limit")) is not None else 5),
            )
            return _json(
                {
                    "action": "preview",
                    "candidates": [_format_result(row) for row in rows],
                    "instruction": "Ask the user to confirm the exact ID before delete if there is any ambiguity.",
                }
            )
        if action == "delete":
            memory_id = str(args.get("id") or "").strip()
            if not memory_id:
                return tool_error("id is required for delete")
            row = self.provider.store.get_by_id(
                memory_id, workspace=self.provider.workspace, user_id=self.provider.user_id
            )
            if not row:
                return tool_error(f"memory not found: {memory_id}")
            try:
                self.provider.store.delete_by_id(memory_id)
            except Exception:
                return tool_error("delete failed")
            return _json({"action": "delete", "deleted": _format_result(row, include_full=True)})
        return tool_error("action must be preview or delete")
