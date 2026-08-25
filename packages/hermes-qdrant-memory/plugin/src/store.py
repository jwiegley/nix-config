import hashlib
import logging
import os
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional

from .embeddings import FastEmbedEmbedder

logger = logging.getLogger(__name__)

COLLECTION = ""
SCHEMA_VERSION = 1


class _NullLock:
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


_NULL_LOCK = _NullLock()


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def content_hash(content: str, *, workspace: str = "", kind: str = "", user_id: str = "") -> str:
    normalized = " ".join((content or "").strip().lower().split())
    payload = f"{kind}\0{workspace}\0{user_id}\0{normalized}"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def stable_turn_id(session_id: str, role: str, content: str, turn_index: int) -> str:
    if not isinstance(turn_index, int) or isinstance(turn_index, bool) or turn_index < 0:
        raise ValueError("turn_index must be a nonnegative integer")
    digest = hashlib.sha256(
        f"{session_id}\0{turn_index}\0{role}\0{content}".encode("utf-8")
    ).hexdigest()[:24]
    return f"turn_{digest}"


def to_qdrant_id(string_id: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_OID, string_id))


def build_filter(
    *,
    workspace: str = "",
    user_id: str = "",
    kind: str = "fact",
    category: str = "",
):
    from .qdrant_rest import FieldCondition, Filter, MatchValue

    must: list = []
    if kind and kind != "any":
        must.append(FieldCondition(key="kind", match=MatchValue(value=kind)))
    if workspace:
        must.append(FieldCondition(key="agent_workspace", match=MatchValue(value=workspace)))
    if user_id:
        # user_id = X OR user_id = '' to match workspace-global memories too
        must.append(
            Filter(
                should=[
                    FieldCondition(key="user_id", match=MatchValue(value=user_id)),
                    FieldCondition(key="user_id", match=MatchValue(value="")),
                ]
            )
        )
    if category:
        must.append(FieldCondition(key="category", match=MatchValue(value=category)))
    return Filter(must=must) if must else None


def _record_to_row(record) -> dict[str, Any]:
    payload = dict(record.payload or {})
    if "id_str" in payload:
        payload["id"] = payload["id_str"]
    if hasattr(record, "score") and record.score is not None:
        payload["_relevance_score"] = record.score
    return payload


def _in_scope(row: dict[str, Any], workspace: str, user_id: str) -> bool:
    # Mirror build_filter: workspace must match exactly. user_id matches the
    # caller or the workspace-global "" rows.
    if workspace and row.get("agent_workspace", "") != workspace:
        return False
    if user_id and row.get("user_id", "") not in (user_id, ""):
        return False
    return True


class QdrantStore:
    """Qdrant store with dense and sparse named vectors."""

    def __init__(
        self,
        hermes_home: str | Path,
        embedder: FastEmbedEmbedder,
        *,
        connection_cfg: dict[str, Any] | None = None,
        collection: str = COLLECTION,
    ) -> None:
        self.hermes_home = Path(hermes_home).expanduser()
        self.embedder = embedder
        self._connection_cfg = connection_cfg or {}
        if not isinstance(collection, str) or not collection.strip():
            raise ValueError(
                "Qdrant store requires an explicit nonempty string collection"
            )
        self.collection = collection.strip()
        self._client = None
        self._closed = False
        self._open_lock = threading.Lock()
        # Embedded (local) Qdrant is SQLite+numpy backed and NOT thread-safe.
        self._serialize_io = self._connection_cfg.get("mode", "local") != "remote"
        self._io_lock = threading.RLock()

    def io_guard(self):
        return self._io_lock if self._serialize_io else _NULL_LOCK

    @property
    def client(self):
        if self._closed:
            raise RuntimeError("Qdrant store is closed")
        if self._client is None:
            self._open()
        return self._client

    def _open(self) -> None:
        if self._closed:
            raise RuntimeError("Qdrant store is closed")
        if self._client is not None:
            return
        with self._open_lock:
            if self._closed:
                raise RuntimeError("Qdrant store is closed")
            if self._client is not None:
                return
            self._open_locked()

    def _open_locked(self) -> None:
        from .qdrant_rest import QdrantClient
        from .qdrant_rest import (
            Distance,
            PayloadSchemaType,
            SparseVectorParams,
            VectorParams,
        )

        mode = self._connection_cfg.get("mode", "local")
        if mode == "remote":
            url = self._connection_cfg.get("url") or "http://localhost:6333"
            api_key_env = self._connection_cfg.get("api_key_env")
            api_key = None
            if api_key_env:
                api_key = (os.environ.get(api_key_env) or "").strip()
                if not api_key:
                    raise RuntimeError(
                        f"qdrant credential environment {api_key_env!r} is required"
                    )
            self._client = QdrantClient(url=url, api_key=api_key)
            logger.info("qdrant client: remote (%s)", url)
        else:
            db_path = self._connection_cfg.get("path") or str(self.hermes_home / "qdrant")
            db_path = str(Path(db_path).expanduser())
            Path(db_path).mkdir(parents=True, exist_ok=True)
            self._client = QdrantClient(path=db_path)
            logger.info("qdrant client: local (%s)", db_path)

        existing = {c.name for c in self._client.get_collections().collections}
        if self.collection not in existing:
            self._client.create_collection(
                collection_name=self.collection,
                vectors_config={
                    "dense": VectorParams(size=self.embedder.dim, distance=Distance.COSINE)
                },
                sparse_vectors_config={"sparse": SparseVectorParams()},
            )
            for field, schema in (
                ("kind", PayloadSchemaType.KEYWORD),
                ("agent_workspace", PayloadSchemaType.KEYWORD),
                ("user_id", PayloadSchemaType.KEYWORD),
                ("category", PayloadSchemaType.KEYWORD),
                ("content_hash", PayloadSchemaType.KEYWORD),
                ("session_id", PayloadSchemaType.KEYWORD),
                ("turn_index", PayloadSchemaType.INTEGER),
            ):
                try:
                    self._client.create_payload_index(
                        self.collection, field, schema
                    )
                except Exception:
                    logger.debug("qdrant payload index creation skipped")
            logger.info(
                "qdrant collection '%s' created (dim=%d)", self.collection, self.embedder.dim
            )

    def close(self) -> None:
        with self._open_lock:
            self._closed = True
            client = self._client
            self._client = None
        if client is not None:
            client.close()

    def add_rows(self, rows: list[dict[str, Any]]) -> None:
        if not rows:
            return
        self._open()
        points = self._prepare_rows(rows)
        if points:
            with self.io_guard():
                self.client.upsert(collection_name=self.collection, points=points)

    def add_row(self, row: dict[str, Any]) -> None:
        self.add_rows([row])

    def next_turn_index(self, session_id: str) -> int:
        """Return a restart-stable ordinal for the next turn in a session."""
        from .qdrant_rest import FieldCondition, Filter, MatchValue

        session_id = str(session_id or "").strip()
        if not session_id:
            raise ValueError("session_id is required to restore the turn ordinal")
        turn_filter = Filter(
            must=[
                FieldCondition(key="kind", match=MatchValue(value="turn")),
                FieldCondition(key="session_id", match=MatchValue(value=session_id)),
            ]
        )
        maximum = -1
        offset = None
        seen_offsets: set[str] = set()
        while True:
            with self.io_guard():
                points, next_offset = self.client.scroll(
                    collection_name=self.collection,
                    scroll_filter=turn_filter,
                    limit=256,
                    with_payload=True,
                    with_vectors=False,
                    offset=offset,
                )
            for point in points:
                value = (point.payload or {}).get("turn_index")
                if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
                    maximum = max(maximum, value)
            if next_offset is None:
                return maximum + 1
            marker = str(next_offset)
            if marker in seen_offsets:
                raise RuntimeError("Qdrant turn-index scan repeated a page offset")
            seen_offsets.add(marker)
            offset = next_offset

    def _prepare_rows(self, rows: list[dict[str, Any]]) -> list:
        from .qdrant_rest import PointStruct, SparseVector

        texts = [str(row.get("content") or "") for row in rows]
        dense_vecs = self.embedder.embed(texts)
        sparse_vecs = self.embedder.embed_sparse_batch(texts)
        points = []
        for row, dense_vec, (sparse_indices, sparse_values) in zip(rows, dense_vecs, sparse_vecs):
            payload = dict(row)
            payload.setdefault("id_str", payload["id"])
            payload.setdefault("schema_version", SCHEMA_VERSION)
            payload.setdefault("agent_workspace", "")
            payload.setdefault("user_id", "")
            if isinstance(payload.get("created_at"), datetime):
                payload["created_at"] = payload["created_at"].isoformat()
            points.append(
                PointStruct(
                    id=to_qdrant_id(payload["id_str"]),
                    vector={
                        "dense": dense_vec,
                        "sparse": SparseVector(indices=sparse_indices, values=sparse_values),
                    },
                    payload=payload,
                )
            )
        return points

    def get_by_id(
        self, memory_id: str, *, workspace: str = "", user_id: str = ""
    ) -> Optional[dict[str, Any]]:
        if not memory_id:
            return None
        with self.io_guard():
            results = self.client.retrieve(
                collection_name=self.collection,
                ids=[to_qdrant_id(memory_id)],
                with_payload=True,
                with_vectors=False,
            )
        if not results:
            return None
        row = _record_to_row(results[0])
        return row if _in_scope(row, workspace, user_id) else None

    def get_by_ids(
        self, ids: Iterable[str], *, workspace: str = "", user_id: str = ""
    ) -> list[dict[str, Any]]:
        clean = [str(v) for v in ids if v]
        if not clean:
            return []
        with self.io_guard():
            results = self.client.retrieve(
                collection_name=self.collection,
                ids=[to_qdrant_id(i) for i in clean],
                with_payload=True,
                with_vectors=False,
            )
        rows = [_record_to_row(r) for r in results]
        return [row for row in rows if _in_scope(row, workspace, user_id)]

    def find_by_hash(
        self, digest: str, *, workspace: str = "", user_id: str = "", kind: str = "fact"
    ) -> Optional[dict[str, Any]]:
        from .qdrant_rest import FieldCondition, Filter, MatchValue

        base = build_filter(workspace=workspace, user_id=user_id, kind=kind)
        hash_cond = FieldCondition(key="content_hash", match=MatchValue(value=digest))
        must = [hash_cond, *(base.must if base else [])]
        with self.io_guard():
            points, _ = self.client.scroll(
                collection_name=self.collection,
                scroll_filter=Filter(must=must),
                limit=1,
                with_payload=True,
                with_vectors=False,
            )
        return _record_to_row(points[0]) if points else None

    def delete_by_id(self, memory_id: str) -> None:
        from .qdrant_rest import PointIdsList

        with self.io_guard():
            self.client.delete(
                collection_name=self.collection,
                points_selector=PointIdsList(points=[to_qdrant_id(memory_id)]),
            )
