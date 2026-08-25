"""OpenAI-compatible dense embeddings and local sparse BM25 vectors.

The upstream plugin computes both dense and sparse vectors locally with
``fastembed``. This variant keeps inference behind the configured
OpenAI-compatible endpoint and avoids adding fastembed to Hermes's sealed
Python environment. Sparse vectors remain stateless local arithmetic.

Dense vectors come from ``/v1/embeddings`` using Hermes's existing ``httpx``.
Sparse vectors use plain BM25 term-frequency components; Qdrant supplies IDF.
"""

from __future__ import annotations

import logging
import math
import os
import re
import threading
import zlib
from collections import Counter
from typing import Any, Dict, List, Sequence, Tuple

logger = logging.getLogger(__name__)

# Matches the bridge/gateway default. models.nix embedding.primary is the single
# embedding model the backend serves; the Nix wrapper passes it explicitly.
DEFAULT_DENSE_MODEL = os.environ.get("HERMES_QDRANT_EMBED_MODEL", "bge-m3-mlx-fp16")
DEFAULT_DENSE_DIMENSION = 1024
DEFAULT_SPARSE_MODEL = "bm25-local"

# Same base URL the agent uses for chat completions.
GATEWAY_BASE = os.environ.get(
    "HERMES_QDRANT_EMBED_BASE_URL",
    os.environ.get("OPENROUTER_BASE_URL", "http://127.0.0.1:8000/v1"),
).rstrip("/")

EMBED_TIMEOUT = float(os.environ.get("HERMES_QDRANT_EMBED_TIMEOUT", "60"))

# Batch cap. bge-m3 is a large model; a whole memory flush in one request can
# blow the backend's per-request budget, and one oversized request failing loses
# the entire batch rather than one chunk of it.
MAX_BATCH = int(os.environ.get("HERMES_QDRANT_EMBED_BATCH", "32"))

_TOKEN_RE = re.compile(r"[a-z0-9]+")

# BM25 constants. k1/b are the standard defaults. AVG_LEN is a FIXED assumed
# average document length: with no corpus statistics we cannot compute a real
# one, and fastembed's own Bm25 does the same thing for the same reason. It only
# affects length normalisation, and identically at index and query time.
BM25_K1 = 1.2
BM25_B = 0.75
BM25_AVG_LEN = 256.0


class BM25Sparse:
    """Stateless BM25 sparse vectoriser.

    Emits only the term-frequency component of BM25. The inverse-document-
    frequency half is applied by QDRANT, because the sparse vector index is
    created with ``modifier="idf"`` (see qdrant_rest.SparseVectorParams). That
    split is what makes this stateless: no vocabulary, no document counts, no
    state to keep consistent between index and query time.

    Token -> index uses ``zlib.crc32``, NOT the builtin ``hash()``. ``hash()``
    is salted per process (PYTHONHASHSEED), so a memory written by one agent
    process would be unqueryable by the next one — a silent recall failure that
    would look like "memory isn't working" with nothing in the logs.

    NOTE this is deliberately NOT wire-compatible with fastembed's
    ``Qdrant/bm25``. It only has to agree with itself. A collection previously
    populated by upstream-with-fastembed could not be sparse-queried by this
    code; that is irrelevant here because the collection is created fresh.
    """

    def __init__(self, avg_len: float = BM25_AVG_LEN) -> None:
        self.avg_len = avg_len

    @staticmethod
    def _tokenize(text: str) -> List[str]:
        # Length >= 2 drops the single-character noise that otherwise dominates
        # the hash space without carrying retrieval signal.
        return [t for t in _TOKEN_RE.findall((text or "").lower()) if len(t) >= 2]

    @staticmethod
    def _index(token: str) -> int:
        # 31-bit: Qdrant sparse indices are unsigned, and staying under 2^31
        # avoids any signedness ambiguity in JSON round-tripping.
        return zlib.crc32(token.encode("utf-8")) & 0x7FFFFFFF

    def encode(self, text: str) -> Tuple[List[int], List[float]]:
        tokens = self._tokenize(text)
        if not tokens:
            # Qdrant rejects a sparse vector with empty indices, and upstream's
            # callers expect a usable pair, so emit a single inert term.
            return [0], [0.0]
        counts = Counter(tokens)
        doc_len = len(tokens)
        norm = BM25_K1 * (1.0 - BM25_B + BM25_B * (doc_len / self.avg_len))
        merged: Dict[int, float] = {}
        for token, tf in counts.items():
            weight = (tf * (BM25_K1 + 1.0)) / (tf + norm)
            idx = self._index(token)
            # crc32 collisions are rare but must not silently drop a term;
            # summing is the same thing the term appearing twice would do.
            merged[idx] = merged.get(idx, 0.0) + weight
        indices = sorted(merged)
        return indices, [merged[i] for i in indices]


class GatewayEmbedder:
    """Dense embeddings from the LLM gateway; sparse computed locally.

    Keeps upstream's FastEmbedEmbedder method surface exactly, so store.py and
    retrieval.py need no changes: dim, warm, embed_one, embed, embed_sparse,
    embed_sparse_batch.
    """

    def __init__(
        self,
        model_name: str = DEFAULT_DENSE_MODEL,
        *,
        sparse_model_name: str = DEFAULT_SPARSE_MODEL,
        base_url: str = GATEWAY_BASE,
        api_key_env: str | None = "OPENAI_API_KEY",
        dimension: int = DEFAULT_DENSE_DIMENSION,
        **_: Any,
    ) -> None:
        if not isinstance(dimension, int) or isinstance(dimension, bool) or dimension <= 0:
            raise ValueError("embedding dimension must be a positive integer")
        self.model_name = model_name or DEFAULT_DENSE_MODEL
        self.sparse_model_name = sparse_model_name or DEFAULT_SPARSE_MODEL
        self.base_url = (base_url or GATEWAY_BASE).rstrip("/")
        self.api_key_env = api_key_env
        self._dim = dimension
        self._sparse = BM25Sparse()
        self._lock = threading.Lock()
        self._client = None
        self._closed = False

    # -- dense -------------------------------------------------------------

    def _http(self):
        if self._closed:
            raise RuntimeError("embedding client is closed")
        if self._client is None:
            with self._lock:
                if self._closed:
                    raise RuntimeError("embedding client is closed")
                if self._client is None:
                    import httpx

                    api_key = (
                        (os.environ.get(self.api_key_env) or "").strip()
                        if self.api_key_env
                        else ""
                    )
                    if self.api_key_env and not api_key:
                        raise RuntimeError(
                            f"embedding credential environment {self.api_key_env!r} is required"
                        )
                    headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
                    self._client = httpx.Client(
                        timeout=EMBED_TIMEOUT,
                        headers=headers,
                        trust_env=False,
                    )
        return self._client

    def _post_batch(self, texts: Sequence[str]) -> List[List[float]]:
        resp = self._http().post(
            f"{self.base_url}/embeddings",
            json={"model": self.model_name, "input": list(texts)},
        )
        if resp.status_code >= 400:
            raise RuntimeError(f"embedding gateway HTTP {resp.status_code}")
        payload = resp.json()
        data = payload.get("data")
        if not isinstance(data, list) or len(data) != len(texts):
            raise RuntimeError(
                f"embedding gateway returned {len(data) if isinstance(data, list) else 'no'} "
                f"vectors for {len(texts)} input(s)"
            )
        if not all(isinstance(item, dict) for item in data):
            raise RuntimeError("embedding gateway returned a malformed data item")
        indices = [item.get("index") for item in data]
        if not all(isinstance(index, int) and not isinstance(index, bool) for index in indices):
            raise RuntimeError("embedding gateway returned a non-integer index")
        if sorted(indices) != list(range(len(texts))):
            raise RuntimeError("embedding gateway returned duplicate, missing, or invalid indices")

        # Sort by index: the OpenAI schema does not promise response order, and
        # a silently permuted batch would attach each memory to the wrong vector
        # — corrupt recall with no error anywhere.
        ordered = sorted(data, key=lambda item: item["index"])
        vectors: List[List[float]] = []
        for item in ordered:
            vector = item.get("embedding")
            if not isinstance(vector, list) or not vector:
                raise RuntimeError("embedding gateway returned an empty or malformed vector")
            if any(
                isinstance(value, bool)
                or not isinstance(value, (int, float))
                or not math.isfinite(value)
                for value in vector
            ):
                raise RuntimeError("embedding gateway returned a non-finite or nonnumeric vector")
            if len(vector) != self._dim:
                raise RuntimeError(
                    f"embedding gateway returned dimension {len(vector)}; expected {self._dim}"
                )
            vectors.append([float(value) for value in vector])
        return vectors

    def embed(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        clean = [t if t else " " for t in texts]
        out: List[List[float]] = []
        for start in range(0, len(clean), MAX_BATCH):
            out.extend(self._post_batch(clean[start : start + MAX_BATCH]))
        return out

    def embed_one(self, text: str) -> List[float]:
        return self.embed([text])[0]

    @property
    def dim(self) -> int:
        return self._dim

    def warm(self) -> int:
        """Resolve the vector dimension.

        Unlike upstream this loads no model — it is a single small gateway call,
        which also serves as an early, loud check that the gateway is reachable
        before any memory write is attempted.
        """
        self.embed_one("dim probe")
        logger.info("qdrant memory: dense dim=%d via %s", self._dim, self.base_url)
        return self._dim

    def close(self) -> None:
        """Close the reusable HTTP client after Hermes drains provider work."""
        with self._lock:
            self._closed = True
            client = self._client
            self._client = None
        if client is not None:
            client.close()

    # -- sparse ------------------------------------------------------------

    def embed_sparse(self, text: str) -> tuple[list[int], list[float]]:
        return self._sparse.encode(text)

    def embed_sparse_batch(self, texts: list[str]) -> list[tuple[list[int], list[float]]]:
        return [self._sparse.encode(t if t else " ") for t in (texts or [])]


# Upstream name kept as an alias so any stray reference still resolves.
FastEmbedEmbedder = GatewayEmbedder


def embedder_from_config(embedding_cfg: Dict[str, Any] | None) -> GatewayEmbedder:
    cfg = embedding_cfg or {}
    return GatewayEmbedder(
        cfg.get("model") or DEFAULT_DENSE_MODEL,
        sparse_model_name=cfg.get("sparse_model") or DEFAULT_SPARSE_MODEL,
        base_url=cfg.get("base_url") or GATEWAY_BASE,
        api_key_env=cfg.get("api_key_env", "OPENAI_API_KEY"),
        dimension=cfg.get("dimension", DEFAULT_DENSE_DIMENSION),
    )
