"""Minimal httpx-backed stand-in for the parts of ``qdrant_client`` this plugin uses.

VENDORED ADDITION -- not upstream. Upstream imports the real ``qdrant-client``
package, which cannot be delivered on this host:
``nix/hermes-agent.nix`` computes ``requiredPythonModules`` over
``extraPythonPackages`` and FAILS THE BUILD if any name collides with the
hermes sealed venv. ``qdrant-client``'s closure collides on fifteen names
(anyio, certifi, h11, httpcore, httpx, idna, packaging, protobuf, pydantic,
pydantic-core, setuptools, sniffio, typing-extensions, typing-inspection,
urllib3), so it is not installable here at any version.

``httpx`` IS already in the sealed venv, so this shim needs no new dependency
and never touches the collision guard.

Scope is deliberately the exact surface ``store.py`` and ``retrieval.py`` touch
and nothing more -- 8 client methods and the model classes below. It is NOT a
general qdrant-client replacement; do not grow it into one. If upstream starts
using another method, add it here explicitly rather than guessing.

Everything speaks Qdrant's HTTP REST API. gRPC (6334) is deliberately not
supported, which is why only 6333 is opened to this guest.
"""

from __future__ import annotations

import logging
import os
import ssl
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

logger = logging.getLogger(__name__)

DEFAULT_TIMEOUT = 30.0


# ---------------------------------------------------------------------------
# Enum-ish constants. Values are the literal strings Qdrant's REST API expects.
# ---------------------------------------------------------------------------


class Distance:
    COSINE = "Cosine"
    EUCLID = "Euclid"
    DOT = "Dot"


class PayloadSchemaType:
    KEYWORD = "keyword"
    INTEGER = "integer"
    FLOAT = "float"
    BOOL = "bool"


class Fusion:
    RRF = "rrf"
    DBSF = "dbsf"


# ---------------------------------------------------------------------------
# Request-body value objects. Each knows how to serialise ITSELF; nothing else
# needs to know the wire format.
# ---------------------------------------------------------------------------


def _enc(value: Any) -> Any:
    """Recursively serialise shim objects, leaving plain JSON values alone."""
    if hasattr(value, "_json"):
        return value._json()
    if isinstance(value, dict):
        return {k: _enc(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_enc(v) for v in value]
    return value


class VectorParams:
    def __init__(self, size: int, distance: str = Distance.COSINE) -> None:
        self.size = size
        self.distance = distance

    def _json(self) -> Dict[str, Any]:
        return {"size": self.size, "distance": self.distance}


class SparseVectorParams:
    """Sparse vector config.

    ``modifier="idf"`` is set so Qdrant applies inverse-document-frequency
    weighting server-side. That is what lets the BM25 side of embeddings.py stay
    stateless: it emits raw term-frequency components and never needs corpus
    statistics of its own.
    """

    def __init__(self, modifier: Optional[str] = "idf") -> None:
        self.modifier = modifier

    def _json(self) -> Dict[str, Any]:
        return {"modifier": self.modifier} if self.modifier else {}


class SparseVector:
    def __init__(self, indices: Sequence[int], values: Sequence[float]) -> None:
        self.indices = list(indices)
        self.values = list(values)

    def _json(self) -> Dict[str, Any]:
        return {"indices": self.indices, "values": self.values}


class MatchValue:
    def __init__(self, value: Any) -> None:
        self.value = value

    def _json(self) -> Dict[str, Any]:
        return {"value": self.value}


class FieldCondition:
    def __init__(self, key: str, match: Optional[MatchValue] = None) -> None:
        self.key = key
        self.match = match

    def _json(self) -> Dict[str, Any]:
        out: Dict[str, Any] = {"key": self.key}
        if self.match is not None:
            out["match"] = _enc(self.match)
        return out


class Filter:
    def __init__(self, must=None, should=None, must_not=None) -> None:
        self.must = must
        self.should = should
        self.must_not = must_not

    def _json(self) -> Dict[str, Any]:
        out: Dict[str, Any] = {}
        for name, val in (("must", self.must), ("should", self.should), ("must_not", self.must_not)):
            if val:
                out[name] = [_enc(v) for v in val]
        return out


class PointStruct:
    def __init__(self, id: Any, vector: Any, payload: Optional[Dict[str, Any]] = None) -> None:
        self.id = id
        self.vector = vector
        self.payload = payload or {}

    def _json(self) -> Dict[str, Any]:
        return {"id": self.id, "vector": _enc(self.vector), "payload": _enc(self.payload)}


class PointIdsList:
    def __init__(self, points: Sequence[Any]) -> None:
        self.points = list(points)

    def _json(self) -> Dict[str, Any]:
        return {"points": self.points}


class Prefetch:
    def __init__(self, query: Any, using: str, limit: int, filter: Optional[Filter] = None) -> None:
        self.query = query
        self.using = using
        self.limit = limit
        self.filter = filter

    def _json(self) -> Dict[str, Any]:
        out: Dict[str, Any] = {"query": _enc(self.query), "using": self.using, "limit": self.limit}
        if self.filter is not None:
            f = _enc(self.filter)
            if f:
                out["filter"] = f
        return out


class FusionQuery:
    def __init__(self, fusion: str = Fusion.RRF) -> None:
        self.fusion = fusion

    def _json(self) -> Dict[str, Any]:
        return {"fusion": self.fusion}


# ---------------------------------------------------------------------------
# Response value objects
# ---------------------------------------------------------------------------


class Record:
    """A returned point. ``_record_to_row`` reads .payload and, if present, .score."""

    __slots__ = ("id", "payload", "vector", "score")

    def __init__(self, raw: Dict[str, Any]) -> None:
        self.id = raw.get("id")
        self.payload = raw.get("payload") or {}
        self.vector = raw.get("vector")
        # Deliberately None rather than absent for scroll/retrieve results:
        # _record_to_row checks `is not None`, so a None score simply means
        # "not a scored query" instead of injecting a bogus 0.0 relevance.
        self.score = raw.get("score")


class _CollectionName:
    __slots__ = ("name",)

    def __init__(self, name: str) -> None:
        self.name = name


class _CollectionsResponse:
    __slots__ = ("collections",)

    def __init__(self, names: Iterable[str]) -> None:
        self.collections = [_CollectionName(n) for n in names]


class _QueryResponse:
    __slots__ = ("points",)

    def __init__(self, points: List[Record]) -> None:
        self.points = points


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------


class QdrantClient:
    """REST-only Qdrant client covering this plugin's needs.

    Accepts ``path=`` for signature compatibility with upstream's local/embedded
    mode, but REFUSES it: embedded mode would put the vector store inside the
    guest's ephemeral state instead of the host's managed, backed-up Qdrant.
    Failing loudly beats silently writing memories somewhere they will be lost.
    """

    def __init__(
        self,
        url: Optional[str] = None,
        api_key: Optional[str] = None,
        path: Optional[str] = None,
        timeout: float = DEFAULT_TIMEOUT,
    ) -> None:
        if path is not None and url is None:
            raise NotImplementedError(
                "embedded/local Qdrant is not supported by this build; "
                "set memory config connection.mode='remote' with a url"
            )
        import httpx

        self._base = (url or "http://127.0.0.1:6333").rstrip("/")
        headers = {"Content-Type": "application/json"}
        if api_key:
            headers["api-key"] = api_key
        verify: ssl.SSLContext | bool = True
        if self._base.startswith("https://"):
            ca_file = (os.environ.get("SSL_CERT_FILE") or "").strip()
            if not ca_file:
                raise RuntimeError(
                    "SSL_CERT_FILE is required for remote Qdrant TLS verification"
                )
            try:
                verify = ssl.create_default_context(cafile=ca_file)
            except (OSError, ssl.SSLError) as exc:
                raise RuntimeError(
                    "could not initialize remote Qdrant TLS verification"
                ) from exc
        self._http = httpx.Client(
            base_url=self._base,
            headers=headers,
            timeout=timeout,
            trust_env=False,
            verify=verify,
        )

    # -- internals ---------------------------------------------------------

    def _request(self, method: str, path: str, *, json: Any = None, params: Any = None) -> Any:
        resp = self._http.request(method, path, json=json, params=params)
        if resp.status_code >= 400:
            raise RuntimeError(f"qdrant {method} {path} -> HTTP {resp.status_code}")
        body = resp.json()
        return body.get("result") if isinstance(body, dict) else body

    def close(self) -> None:
        try:
            self._http.close()
        except Exception:  # noqa: BLE001
            pass

    # -- collection management --------------------------------------------

    def get_collections(self) -> _CollectionsResponse:
        result = self._request("GET", "/collections") or {}
        return _CollectionsResponse([c.get("name") for c in result.get("collections", [])])

    def create_collection(
        self,
        collection_name: str,
        vectors_config: Dict[str, VectorParams],
        sparse_vectors_config: Optional[Dict[str, SparseVectorParams]] = None,
    ) -> None:
        body: Dict[str, Any] = {"vectors": {k: _enc(v) for k, v in vectors_config.items()}}
        if sparse_vectors_config:
            body["sparse_vectors"] = {k: _enc(v) for k, v in sparse_vectors_config.items()}
        self._request("PUT", f"/collections/{collection_name}", json=body)

    def create_payload_index(
        self, collection_name: str, field_name: str, field_schema: str
    ) -> None:
        self._request(
            "PUT",
            f"/collections/{collection_name}/index",
            json={"field_name": field_name, "field_schema": field_schema},
            params={"wait": "true"},
        )

    # -- points ------------------------------------------------------------

    def upsert(self, collection_name: str, points: Sequence[PointStruct]) -> None:
        self._request(
            "PUT",
            f"/collections/{collection_name}/points",
            json={"points": [_enc(p) for p in points]},
            params={"wait": "true"},
        )

    def retrieve(
        self,
        collection_name: str,
        ids: Sequence[Any],
        with_payload: bool = True,
        with_vectors: bool = False,
    ) -> List[Record]:
        result = self._request(
            "POST",
            f"/collections/{collection_name}/points",
            json={"ids": list(ids), "with_payload": with_payload, "with_vector": with_vectors},
        )
        return [Record(r) for r in (result or [])]

    def scroll(
        self,
        collection_name: str,
        scroll_filter: Optional[Filter] = None,
        limit: int = 10,
        with_payload: bool = True,
        with_vectors: bool = False,
        offset: Any = None,
    ) -> Tuple[List[Record], Any]:
        body: Dict[str, Any] = {
            "limit": limit,
            "with_payload": with_payload,
            "with_vector": with_vectors,
        }
        if scroll_filter is not None:
            f = _enc(scroll_filter)
            if f:
                body["filter"] = f
        if offset is not None:
            body["offset"] = offset
        result = self._request(
            "POST", f"/collections/{collection_name}/points/scroll", json=body
        ) or {}
        points = [Record(r) for r in result.get("points", [])]
        # Upstream unpacks `points, _ = client.scroll(...)`, so the tuple shape
        # is load-bearing even though the offset is currently discarded.
        return points, result.get("next_page_offset")

    def delete(self, collection_name: str, points_selector: Any) -> None:
        body = _enc(points_selector)
        if isinstance(body, dict) and "points" in body:
            payload: Dict[str, Any] = {"points": body["points"]}
        else:
            payload = {"filter": body}
        self._request(
            "POST",
            f"/collections/{collection_name}/points/delete",
            json=payload,
            params={"wait": "true"},
        )

    def query_points(
        self,
        collection_name: str,
        query: Any = None,
        using: Optional[str] = None,
        prefetch: Optional[Sequence[Prefetch]] = None,
        query_filter: Optional[Filter] = None,
        limit: int = 10,
        with_payload: bool = True,
    ) -> _QueryResponse:
        body: Dict[str, Any] = {"limit": limit, "with_payload": with_payload}
        if query is not None:
            body["query"] = _enc(query)
        if using:
            body["using"] = using
        if prefetch:
            body["prefetch"] = [_enc(p) for p in prefetch]
        if query_filter is not None:
            f = _enc(query_filter)
            if f:
                body["filter"] = f
        result = self._request(
            "POST", f"/collections/{collection_name}/points/query", json=body
        ) or {}
        return _QueryResponse([Record(r) for r in result.get("points", [])])
