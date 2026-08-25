#!/usr/bin/env python3
"""Behavioral contract for the vendored Hermes Qdrant memory plugin."""

from __future__ import annotations

import importlib
import importlib.util
import json
import os
import sys
import tempfile
import types
from contextlib import nullcontext
from pathlib import Path


def load_plugin(root: Path):
    agent = types.ModuleType("agent")
    agent.__path__ = []
    memory_provider = types.ModuleType("agent.memory_provider")

    class MemoryProvider:
        pass

    memory_provider.MemoryProvider = MemoryProvider
    sys.modules["agent"] = agent
    sys.modules["agent.memory_provider"] = memory_provider

    tools_package = types.ModuleType("tools")
    tools_package.__path__ = []
    tools_registry = types.ModuleType("tools.registry")

    def tool_error(message, **extra):
        payload = {"error": str(message)}
        payload.update(extra)
        return json.dumps(payload, ensure_ascii=False)

    tools_registry.tool_error = tool_error
    sys.modules["tools"] = tools_package
    sys.modules["tools.registry"] = tools_registry

    parent_name = "_hermes_user_memory"
    parent = types.ModuleType(parent_name)
    parent.__path__ = []
    sys.modules[parent_name] = parent
    module_name = f"{parent_name}.nix-managed-hermes-qdrant-memory"
    spec = importlib.util.spec_from_file_location(
        module_name,
        root / "__init__.py",
        submodule_search_locations=[str(root)],
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module_name, module


class Embedder:
    dim = 3

    def embed(self, texts):
        return [[0.1, 0.2, 0.3] for _ in texts]

    def embed_one(self, _text):
        return [0.1, 0.2, 0.3]

    def embed_sparse(self, _text):
        return [7], [1.0]

    def embed_sparse_batch(self, texts):
        return [([7], [1.0]) for _ in texts]


class Response:
    status_code = 200
    text = ""

    def __init__(self, result):
        self._result = result

    def json(self):
        return {"result": self._result}


class FakeHttp:
    def __init__(self):
        self.requests = []

    def request(self, method, path, *, json=None, params=None):
        self.requests.append((method, path, json, params))
        if path == "/collections":
            result = {
                "collections": [
                    {"name": "assistant"},
                    {"name": "archive"},
                ]
            }
        elif path.endswith("/points/scroll"):
            result = {
                "points": [
                    {
                        "id": "scroll-point",
                        "payload": {"id_str": "memory-scroll", "content": "scroll result"},
                        "vector": None,
                    }
                ],
                "next_page_offset": "next-offset",
            }
        elif path.endswith("/points/query"):
            result = {
                "points": [
                    {
                        "id": "query-point",
                        "payload": {"id_str": "memory-query", "content": "query result"},
                        "score": 0.875,
                    }
                ]
            }
        elif method == "POST" and path.endswith("/points"):
            result = [
                {
                    "id": "retrieve-point",
                    "payload": {"id_str": "memory-retrieve", "content": "retrieve result"},
                    "vector": None,
                }
            ]
        else:
            result = {}
        return Response(result)

    def close(self):
        pass


def main() -> None:
    root = Path(sys.argv[1]).resolve()
    module_name, plugin = load_plugin(root)
    config = sys.modules[f"{module_name}.src.config"]
    embeddings = sys.modules[f"{module_name}.src.embeddings"]
    rest = importlib.import_module(f"{module_name}.src.qdrant_rest")
    retrieval = sys.modules[f"{module_name}.src.retrieval"]
    store_module = sys.modules[f"{module_name}.src.store"]
    tools_module = sys.modules[f"{module_name}.src.tools"]
    assert tools_module.tool_error is sys.modules["tools.registry"].tool_error

    assert config.DEFAULTS["collection"] == ""
    assert config.DEFAULTS["connection"]["api_key_env"] == "QDRANT_API_KEY"
    assert config.DEFAULTS["embedding"]["api_key_env"] == "OPENAI_API_KEY"
    assert config.DEFAULTS["embedding"]["dimension"] == 1024
    assert "api_key_file" not in (root / "src/store.py").read_text()
    assert "_PACKAGE_NAME" not in (root / "__init__.py").read_text()

    unknown_tool_error = tools_module.QdrantToolDispatcher(None).handle(
        "not-a-qdrant-tool", {}
    )
    assert unknown_tool_error == sys.modules["tools.registry"].tool_error(
        "Unknown Qdrant memory tool: not-a-qdrant-tool"
    )

    # A malformed managed config must fail closed rather than selecting the
    # legacy default collection. Supply the two Hermes imports load_config uses
    # without reading any real user state.
    with tempfile.TemporaryDirectory() as directory:
        hermes_home = Path(directory)
        (hermes_home / "config.yaml").write_text("plugins: [not-a-mapping")
        hermes_cli = types.ModuleType("hermes_cli")
        hermes_cli.__path__ = []
        hermes_cli_config = types.ModuleType("hermes_cli.config")
        hermes_cli_config.cfg_get = lambda raw, *keys, default=None: default
        hermes_constants = types.ModuleType("hermes_constants")
        hermes_constants.get_hermes_home = lambda: hermes_home
        sys.modules["hermes_cli"] = hermes_cli
        sys.modules["hermes_cli.config"] = hermes_cli_config
        sys.modules["hermes_constants"] = hermes_constants
        try:
            config.load_config()
        except RuntimeError as exc:
            assert "managed Qdrant plugin configuration" in str(exc)
        else:
            raise AssertionError("malformed Qdrant configuration fell back silently")

    provider = plugin.QdrantMemoryProvider()
    assert not hasattr(provider, "post_setup")
    provider._config = {"connection": {"mode": "remote"}}
    provider._embedder = Embedder()
    provider._resolve_hermes_home = lambda: "/nonexistent/hermes-home"
    try:
        _ = provider.store
    except RuntimeError as exc:
        assert "explicit nonempty string collection" in str(exc)
    else:
        raise AssertionError("Qdrant provider fell back to an implicit collection")

    provider = plugin.QdrantMemoryProvider()
    provider._config = {"collection": 123, "connection": {"mode": "remote"}}
    provider._embedder = Embedder()
    provider._resolve_hermes_home = lambda: "/nonexistent/hermes-home"
    try:
        _ = provider.store
    except RuntimeError as exc:
        assert "explicit nonempty string collection" in str(exc)
    else:
        raise AssertionError("Qdrant provider coerced a non-string collection")

    provider = plugin.QdrantMemoryProvider()
    provider._config = {
        "collection": "assistant",
        "connection": {"mode": "remote", "api_key_env": "QDRANT_API_KEY"},
    }
    provider._embedder = Embedder()
    provider._resolve_hermes_home = lambda: "/nonexistent/hermes-home"
    assert provider.store.collection == "assistant"

    try:
        store_module.QdrantStore("/nonexistent", Embedder())
    except ValueError as exc:
        assert "explicit nonempty string collection" in str(exc)
    else:
        raise AssertionError("QdrantStore accepted an implicit collection")

    try:
        store_module.QdrantStore("/nonexistent", Embedder(), collection=123)
    except ValueError as exc:
        assert "explicit nonempty string collection" in str(exc)
    else:
        raise AssertionError("QdrantStore coerced a non-string collection")

    class ScopeClient:
        def __init__(self, payloads):
            self.records = {
                store_module.to_qdrant_id(memory_id): rest.Record(
                    {
                        "id": store_module.to_qdrant_id(memory_id),
                        "payload": {"id_str": memory_id, **payload},
                    }
                )
                for memory_id, payload in payloads.items()
            }
            self.delete_calls = []

        def retrieve(self, *, collection_name, ids, with_payload, with_vectors):
            assert collection_name == "assistant"
            assert with_payload is True
            assert with_vectors is False
            return [
                self.records[memory_id]
                for memory_id in ids
                if memory_id in self.records
            ]

        def delete(self, *, collection_name, points_selector):
            assert collection_name == "assistant"
            self.delete_calls.append(points_selector.points)

    workspace = "/Users/johnw/src/nix"
    scope_client = ScopeClient(
        {
            "memory-match": {
                "kind": "fact",
                "content": "remove this exact memory",
                "agent_workspace": workspace,
                "user_id": "johnw",
                "provenance_turn_ids": [
                    "turn-match",
                    "turn-wrong-workspace",
                    "turn-wrong-user",
                    "turn-global",
                ],
            },
            "memory-wrong-workspace": {
                "kind": "fact",
                "content": "another workspace",
                "agent_workspace": "/Users/johnw/src/other",
                "user_id": "johnw",
            },
            "memory-wrong-user": {
                "kind": "fact",
                "content": "another user",
                "agent_workspace": workspace,
                "user_id": "mallory",
            },
            "memory-global": {
                "kind": "fact",
                "content": "workspace-global memory",
                "agent_workspace": workspace,
                "user_id": "",
            },
            "turn-match": {
                "kind": "turn",
                "content": "matching provenance",
                "agent_workspace": workspace,
                "user_id": "johnw",
            },
            "turn-wrong-workspace": {
                "kind": "turn",
                "content": "another workspace provenance",
                "agent_workspace": "/Users/johnw/src/other",
                "user_id": "johnw",
            },
            "turn-wrong-user": {
                "kind": "turn",
                "content": "another user provenance",
                "agent_workspace": workspace,
                "user_id": "mallory",
            },
            "turn-global": {
                "kind": "turn",
                "content": "workspace-global provenance",
                "agent_workspace": workspace,
                "user_id": "",
            },
        }
    )
    scope_store = store_module.QdrantStore(
        "/nonexistent",
        Embedder(),
        connection_cfg={"mode": "remote"},
        collection="assistant",
    )
    scope_store._client = scope_client
    scoped_provider = types.SimpleNamespace(
        store=scope_store, workspace=workspace, user_id="johnw"
    )
    dispatcher = tools_module.QdrantToolDispatcher(scoped_provider)

    read = json.loads(
        dispatcher.handle(
            "qdrant_read", {"id": "memory-match", "include_provenance": True}
        )
    )
    assert read["memory"]["id"] == "memory-match"
    assert [row["id"] for row in read["provenance"]] == [
        "turn-match",
        "turn-global",
    ]
    for memory_id in ("memory-wrong-workspace", "memory-wrong-user"):
        denied = json.loads(dispatcher.handle("qdrant_read", {"id": memory_id}))
        assert denied == {"error": f"memory not found: {memory_id}"}
    workspace_global = json.loads(
        dispatcher.handle("qdrant_read", {"id": "memory-global"})
    )
    assert workspace_global["memory"]["id"] == "memory-global"

    for memory_id in ("memory-wrong-workspace", "memory-wrong-user"):
        denied = json.loads(
            dispatcher.handle("qdrant_forget", {"action": "delete", "id": memory_id})
        )
        assert denied == {"error": f"memory not found: {memory_id}"}
    assert scope_client.delete_calls == []
    deleted = json.loads(
        dispatcher.handle(
            "qdrant_forget", {"action": "delete", "id": "memory-match"}
        )
    )
    assert deleted["action"] == "delete"
    assert deleted["deleted"]["id"] == "memory-match"
    assert scope_client.delete_calls == [
        [store_module.to_qdrant_id("memory-match")],
    ]

    original_client = rest.QdrantClient
    created = []
    created_indexes = []

    class RecordingClient:
        def __init__(self, *, url=None, api_key=None, path=None):
            created.append((url, api_key, path))

        def get_collections(self):
            return types.SimpleNamespace(collections=[])

        def create_collection(self, **kwargs):
            self.collection = kwargs

        def create_payload_index(self, *args):
            created_indexes.append(args)

    rest.QdrantClient = RecordingClient
    os.environ.pop("QDRANT_API_KEY", None)
    missing = store_module.QdrantStore(
        "/nonexistent",
        Embedder(),
        connection_cfg={"mode": "remote", "api_key_env": "QDRANT_API_KEY"},
        collection="assistant",
    )
    try:
        missing._open_locked()
    except RuntimeError as exc:
        assert "QDRANT_API_KEY" in str(exc)
    else:
        raise AssertionError("configured Qdrant credential did not fail closed")
    assert created == []

    os.environ["QDRANT_API_KEY"] = "test-only-key"
    authenticated = store_module.QdrantStore(
        "/nonexistent",
        Embedder(),
        connection_cfg={
            "mode": "remote",
            "url": "https://qdrant.example.invalid",
            "api_key_env": "QDRANT_API_KEY",
        },
        collection="assistant",
    )
    authenticated._open_locked()
    assert created == [("https://qdrant.example.invalid", "test-only-key", None)]
    assert authenticated.client.collection["collection_name"] == "assistant"
    assert set(authenticated.client.collection["vectors_config"]) == {"dense"}
    assert set(authenticated.client.collection["sparse_vectors_config"]) == {"sparse"}
    assert created_indexes == [
        ("assistant", "kind", rest.PayloadSchemaType.KEYWORD),
        ("assistant", "agent_workspace", rest.PayloadSchemaType.KEYWORD),
        ("assistant", "user_id", rest.PayloadSchemaType.KEYWORD),
        ("assistant", "category", rest.PayloadSchemaType.KEYWORD),
        ("assistant", "content_hash", rest.PayloadSchemaType.KEYWORD),
        ("assistant", "session_id", rest.PayloadSchemaType.KEYWORD),
        ("assistant", "turn_index", rest.PayloadSchemaType.INTEGER),
    ]
    rest.QdrantClient = original_client
    os.environ.pop("QDRANT_API_KEY", None)

    turn_scan_calls = []

    class TurnPageClient:
        def scroll(self, **kwargs):
            turn_scan_calls.append(kwargs)
            if kwargs["offset"] is None:
                return [
                    types.SimpleNamespace(payload={"turn_index": 0}),
                    types.SimpleNamespace(payload={"turn_index": 3}),
                    types.SimpleNamespace(payload={"turn_index": True}),
                    types.SimpleNamespace(payload={"turn_index": "99"}),
                ], "page-2"
            assert kwargs["offset"] == "page-2"
            return [types.SimpleNamespace(payload={"turn_index": 7})], None

    turn_scan_store = store_module.QdrantStore(
        "/nonexistent",
        Embedder(),
        connection_cfg={"mode": "remote"},
        collection="assistant",
    )
    turn_scan_store._client = TurnPageClient()
    assert turn_scan_store.next_turn_index("resumed-session") == 8
    assert len(turn_scan_calls) == 2
    assert [call["offset"] for call in turn_scan_calls] == [None, "page-2"]
    assert all(
        {
            "collection_name": call["collection_name"],
            "filter": rest._enc(call["scroll_filter"]),
            "limit": call["limit"],
            "with_payload": call["with_payload"],
            "with_vectors": call["with_vectors"],
        }
        == {
            "collection_name": "assistant",
            "filter": {
                "must": [
                    {"key": "kind", "match": {"value": "turn"}},
                    {"key": "session_id", "match": {"value": "resumed-session"}},
                ]
            },
            "limit": 256,
            "with_payload": True,
            "with_vectors": False,
        }
        for call in turn_scan_calls
    )

    import httpx

    original_httpx_client = httpx.Client
    original_ssl_context = rest.ssl.create_default_context
    embedding_clients = []
    ssl_context = object()
    ssl_ca_files = []

    def recording_httpx_client(**kwargs):
        client = types.SimpleNamespace(closed=False)
        client.close = lambda: setattr(client, "closed", True)
        embedding_clients.append((kwargs, client))
        return client

    def recording_ssl_context(*, cafile):
        ssl_ca_files.append(cafile)
        return ssl_context

    def failing_ssl_context(**_kwargs):
        raise OSError("injected unreadable CA")

    httpx.Client = recording_httpx_client
    rest.ssl.create_default_context = recording_ssl_context
    os.environ["SSL_CERT_FILE"] = "/nix/store/test-only-ca-bundle.crt"
    qdrant_http = rest.QdrantClient(
        url="https://qdrant.example.invalid",
        api_key="test-only-key",
        timeout=17,
    )
    assert embedding_clients[0][0] == {
        "base_url": "https://qdrant.example.invalid",
        "headers": {
            "Content-Type": "application/json",
            "api-key": "test-only-key",
        },
        "timeout": 17,
        "trust_env": False,
        "verify": ssl_context,
    }
    assert ssl_ca_files == ["/nix/store/test-only-ca-bundle.crt"]
    qdrant_http_client = embedding_clients[0][1]
    qdrant_http.close()
    assert qdrant_http_client.closed
    os.environ.pop("SSL_CERT_FILE")
    try:
        rest.QdrantClient(url="https://qdrant.example.invalid")
    except RuntimeError as exc:
        assert "SSL_CERT_FILE" in str(exc)
    else:
        raise AssertionError("remote Qdrant TLS accepted a missing CA authority")
    assert len(embedding_clients) == 1
    os.environ["SSL_CERT_FILE"] = "/unreadable/test-only-ca-bundle.crt"
    rest.ssl.create_default_context = failing_ssl_context
    try:
        rest.QdrantClient(url="https://qdrant.example.invalid")
    except RuntimeError as exc:
        assert "initialize remote Qdrant TLS" in str(exc)
    else:
        raise AssertionError("remote Qdrant TLS accepted an unreadable CA authority")
    assert len(embedding_clients) == 1
    os.environ.pop("SSL_CERT_FILE")

    os.environ.pop("OPENAI_API_KEY", None)
    embedder = embeddings.GatewayEmbedder(
        base_url="http://127.0.0.1:8000/v1",
        api_key_env="OPENAI_API_KEY",
    )
    try:
        embedder._http()
    except RuntimeError as exc:
        assert "OPENAI_API_KEY" in str(exc)
    else:
        raise AssertionError("configured embedding credential did not fail closed")
    os.environ["OPENAI_API_KEY"] = "test-only-embedding-key"
    embedder._http()
    assert [settings for settings, _client in embedding_clients[1:]] == [
        {
            "timeout": embeddings.EMBED_TIMEOUT,
            "headers": {"Authorization": "Bearer test-only-embedding-key"},
            "trust_env": False,
        }
    ]
    embedding_client = embedding_clients[1][1]
    embedder.close()
    assert embedding_client.closed
    assert embedder._client is None
    try:
        embedder._http()
    except RuntimeError as exc:
        assert "closed" in str(exc)
    else:
        raise AssertionError("closed embedder lazily reopened its HTTP client")
    httpx.Client = original_httpx_client
    rest.ssl.create_default_context = original_ssl_context
    os.environ.pop("OPENAI_API_KEY", None)

    class EmbeddingResponse:
        status_code = 200
        text = ""

        def __init__(self, data):
            self.data = data

        def json(self):
            return {"data": self.data}

    class EmbeddingHttp:
        def __init__(self, data):
            self.data = data
            self.calls = []

        def post(self, *args, **kwargs):
            self.calls.append((args, kwargs))
            return EmbeddingResponse(self.data)

    first_vector = [float(index) for index in range(1024)]
    second_vector = [float(index + 1024) for index in range(1024)]
    validated = embeddings.GatewayEmbedder(
        model_name="bge-m3-mlx-fp16",
        base_url="http://localhost:8000/v1",
        api_key_env=None,
        dimension=1024,
    )
    validated_http = EmbeddingHttp(
        [
            {"index": 1, "embedding": second_vector},
            {"index": 0, "embedding": first_vector},
        ]
    )
    validated._client = validated_http
    assert validated._post_batch(["first", "second"]) == [
        first_vector,
        second_vector,
    ]
    assert validated_http.calls == [
        (
            ("http://localhost:8000/v1/embeddings",),
            {"json": {"model": "bge-m3-mlx-fp16", "input": ["first", "second"]}},
        )
    ]
    assert validated.dim == 1024
    invalid_embedding_payloads = [
        [
            {"index": 0, "embedding": first_vector},
            {"index": 0, "embedding": second_vector},
        ],
        [
            {"index": 0, "embedding": first_vector},
            {"index": 1, "embedding": [float("nan"), *second_vector[1:]]},
        ],
        [
            {"index": 0, "embedding": first_vector},
            {"index": 1, "embedding": second_vector[:-1]},
        ],
    ]
    for payload in invalid_embedding_payloads:
        validated._client = EmbeddingHttp(payload)
        try:
            validated._post_batch(["first", "second"])
        except RuntimeError:
            pass
        else:
            raise AssertionError("malformed embedding response was accepted")

    http = FakeHttp()
    client = original_client.__new__(original_client)
    client._base = "https://qdrant.example.invalid"
    client._http = http
    collections = client.get_collections()
    assert [collection.name for collection in collections.collections] == [
        "assistant",
        "archive",
    ]
    client.create_collection(
        "assistant",
        {"dense": rest.VectorParams(size=3, distance=rest.Distance.COSINE)},
        {"sparse": rest.SparseVectorParams()},
    )
    client.create_payload_index("assistant", "kind", rest.PayloadSchemaType.KEYWORD)
    client.upsert(
        "assistant",
        [rest.PointStruct(id="point", vector={"dense": [0.1, 0.2, 0.3]}, payload={})],
    )
    retrieved = client.retrieve("assistant", ["point"])
    assert len(retrieved) == 1
    assert retrieved[0].id == "retrieve-point"
    assert retrieved[0].payload == {
        "id_str": "memory-retrieve",
        "content": "retrieve result",
    }
    assert retrieved[0].vector is None
    assert retrieved[0].score is None
    scroll_filter = rest.Filter(
        must=[rest.FieldCondition(key="kind", match=rest.MatchValue(value="fact"))]
    )
    scrolled, next_offset = client.scroll(
        "assistant",
        scroll_filter=scroll_filter,
        limit=4,
        with_payload=True,
        with_vectors=False,
        offset="prior-offset",
    )
    assert len(scrolled) == 1
    assert scrolled[0].id == "scroll-point"
    assert scrolled[0].payload == {
        "id_str": "memory-scroll",
        "content": "scroll result",
    }
    assert scrolled[0].vector is None
    assert scrolled[0].score is None
    assert next_offset == "next-offset"
    client.delete("assistant", rest.PointIdsList(points=["point"]))
    queried = client.query_points(
        "assistant",
        prefetch=[
            rest.Prefetch(query=[0.1, 0.2, 0.3], using="dense", limit=3),
            rest.Prefetch(
                query=rest.SparseVector(indices=[7], values=[1.0]),
                using="sparse",
                limit=3,
            ),
        ],
        query=rest.FusionQuery(fusion=rest.Fusion.RRF),
    )
    assert len(queried.points) == 1
    assert queried.points[0].id == "query-point"
    assert queried.points[0].payload == {
        "id_str": "memory-query",
        "content": "query result",
    }
    assert queried.points[0].score == 0.875
    assert http.requests == [
        ("GET", "/collections", None, None),
        (
            "PUT",
            "/collections/assistant",
            {
                "vectors": {"dense": {"size": 3, "distance": "Cosine"}},
                "sparse_vectors": {"sparse": {"modifier": "idf"}},
            },
            None,
        ),
        (
            "PUT",
            "/collections/assistant/index",
            {"field_name": "kind", "field_schema": "keyword"},
            {"wait": "true"},
        ),
        (
            "PUT",
            "/collections/assistant/points",
            {
                "points": [
                    {
                        "id": "point",
                        "vector": {"dense": [0.1, 0.2, 0.3]},
                        "payload": {},
                    }
                ]
            },
            {"wait": "true"},
        ),
        (
            "POST",
            "/collections/assistant/points",
            {"ids": ["point"], "with_payload": True, "with_vector": False},
            None,
        ),
        (
            "POST",
            "/collections/assistant/points/scroll",
            {
                "limit": 4,
                "with_payload": True,
                "with_vector": False,
                "filter": {"must": [{"key": "kind", "match": {"value": "fact"}}]},
                "offset": "prior-offset",
            },
            None,
        ),
        (
            "POST",
            "/collections/assistant/points/delete",
            {"points": ["point"]},
            {"wait": "true"},
        ),
        (
            "POST",
            "/collections/assistant/points/query",
            {
                "limit": 10,
                "with_payload": True,
                "query": {"fusion": "rrf"},
                "prefetch": [
                    {"query": [0.1, 0.2, 0.3], "using": "dense", "limit": 3},
                    {
                        "query": {"indices": [7], "values": [1.0]},
                        "using": "sparse",
                        "limit": 3,
                    },
                ],
            },
            None,
        ),
    ]

    before = len(http.requests)
    hybrid_store = types.SimpleNamespace(
        collection="assistant",
        client=client,
        embedder=Embedder(),
        io_guard=nullcontext,
    )
    assert retrieval.recall(hybrid_store, "remember this", mode="hybrid") == [
        {
            "id_str": "memory-query",
            "id": "memory-query",
            "content": "query result",
            "_relevance_score": 0.875,
        }
    ]
    _method, path, body, _params = http.requests[before]
    assert path == "/collections/assistant/points/query"
    assert [leg["using"] for leg in body["prefetch"]] == ["dense", "sparse"]
    assert body["query"] == {"fusion": "rrf"}

    class HybridFailureClient:
        def __init__(self):
            self.calls = []

        def query_points(self, **kwargs):
            self.calls.append(kwargs)
            if kwargs.get("prefetch") is None:
                raise AssertionError("hybrid failure retried as vector search")
            raise RuntimeError("injected sparse-leg failure")

    hybrid_failure_client = HybridFailureClient()
    hybrid_failure_store = types.SimpleNamespace(
        collection="assistant",
        client=hybrid_failure_client,
        embedder=Embedder(),
        io_guard=nullcontext,
    )
    try:
        retrieval.recall(hybrid_failure_store, "remember this", mode="hybrid")
    except RuntimeError as exc:
        assert str(exc) == "injected sparse-leg failure"
    else:
        raise AssertionError("hybrid failure was silently degraded to vector search")
    assert len(hybrid_failure_client.calls) == 1
    assert hybrid_failure_client.calls[0]["prefetch"] is not None

    # MemoryManager owns serialization and drain. A provider sync_turn must
    # synchronously hand its exact pair to the store instead of creating a
    # second lossy background queue beside that lifecycle.
    writes = []
    restored_indexes = []

    class RecordingStore:
        client = object()

        def next_turn_index(self, session_id):
            restored_indexes.append(session_id)
            return 4

        def add_rows(self, rows):
            writes.append(rows)

    class WarmEmbedder:
        def warm(self):
            return 1024

    qdrant_module = sys.modules[f"{module_name}.src.qdrant"]
    original_load_config = qdrant_module.load_config
    qdrant_module.load_config = lambda: {}
    resumed_provider = plugin.QdrantMemoryProvider()
    resumed_provider._store = RecordingStore()
    resumed_provider._embedder = WarmEmbedder()
    resumed_provider.initialize("resumed-session", hermes_home="/nonexistent")
    qdrant_module.load_config = original_load_config
    assert restored_indexes == ["resumed-session"]
    assert resumed_provider._message_index == 4

    resumed_provider.sync_turn("repeat", "repeat")
    assert resumed_provider._message_index == 6
    resumed_provider.sync_turn("repeat", "repeat")
    assert len(writes) == 2
    rows = [row for pair in writes for row in pair]
    assert [row["role"] for row in rows] == ["user", "assistant", "user", "assistant"]
    assert [row["content"] for row in rows] == ["repeat"] * 4
    assert [row["turn_index"] for row in rows] == [4, 5, 6, 7]
    assert len({row["id"] for row in rows}) == 4
    assert [row["id"] for row in rows] == [
        store_module.stable_turn_id("resumed-session", "user", "repeat", 4),
        store_module.stable_turn_id("resumed-session", "assistant", "repeat", 5),
        store_module.stable_turn_id("resumed-session", "user", "repeat", 6),
        store_module.stable_turn_id("resumed-session", "assistant", "repeat", 7),
    ]

    # A raw Hermes transcript is not a sequence of completed sync_turn pairs:
    # it can contain interim assistants, tool rows, synthetic continuations,
    # and an active unsynced pair. Extraction must not fabricate turn IDs from
    # those transcript positions, even when the model returns evidence indexes.
    extraction_transcript = [
        {"role": "user", "content": "repeat"},
        {"role": "assistant", "content": "interim tool call"},
        {"role": "tool", "content": "tool result"},
        {"role": "assistant", "content": "repeat"},
        {"role": "user", "content": "repeat"},
        {"role": "assistant", "content": "active unsynced repeat"},
    ]
    extraction_inputs = []
    extraction_writes = []

    class ExtractionStore:
        def add_row(self, row):
            extraction_writes.append(row)

    extraction_provider = plugin.QdrantMemoryProvider()
    extraction_provider._store = ExtractionStore()
    extraction_provider._config = {
        "extraction": {"enabled": True, "min_turns": 1},
        "write_filter": {},
    }
    extraction_provider._session_id = "resumed-session"
    extraction_provider.existing_fact = lambda _row: None
    original_extract = qdrant_module.extract

    def fake_extract(messages, context):
        extraction_inputs.append((messages, context))
        return [
            {
                "content": "durable fact",
                "category": "general",
                "tags": ["test"],
                "evidence": [0, 1, 3, 4, 5],
            }
        ]

    qdrant_module.extract = fake_extract
    try:
        inserted = extraction_provider._extract_and_store(
            extraction_transcript,
            source="pre_compress",
        )
    finally:
        qdrant_module.extract = original_extract
    assert extraction_inputs[0][0] == extraction_transcript
    assert inserted == extraction_writes
    assert len(inserted) == 1
    assert inserted[0]["provenance_turn_ids"] == []

    # queue_prefetch is already called from MemoryManager's serialized worker;
    # it must not create another daemon thread beside that lifecycle.
    prefetch_provider = plugin.QdrantMemoryProvider()
    prefetch_provider._initialized = True
    prefetch_provider._config = {"retrieval": {"mode": "hybrid", "top_k": 7}}
    recall_calls = []
    prefetch_provider.recall = lambda query, **kwargs: recall_calls.append((query, kwargs)) or [
        {"content": "remembered"}
    ]
    original_format_prefetch = qdrant_module.format_prefetch
    original_thread = qdrant_module.threading.Thread
    qdrant_module.format_prefetch = lambda _rows: "ready memory"
    qdrant_module.threading.Thread = lambda *_args, **_kwargs: (_ for _ in ()).throw(
        AssertionError("provider created a nested prefetch thread")
    )
    prefetch_provider.queue_prefetch("next question")
    qdrant_module.format_prefetch = original_format_prefetch
    qdrant_module.threading.Thread = original_thread
    assert recall_calls == [
        ("next question", {"mode": "hybrid", "kind": "fact", "limit": 5})
    ]
    assert prefetch_provider.prefetch("ignored") == "ready memory"
    assert prefetch_provider.prefetch("ignored") == ""

    # If MemoryManager's bounded drain detaches an active prefetch, shutdown
    # invalidates its generation before closing clients. The stale operation
    # must not publish into the retired provider after it eventually returns.
    stale_provider = plugin.QdrantMemoryProvider()
    stale_provider._initialized = True
    stale_provider._config = {"retrieval": {"mode": "vector", "top_k": 5}}
    stale_provider._store = types.SimpleNamespace(close=lambda: None)
    stale_provider._embedder = types.SimpleNamespace(close=lambda: None)

    def stale_recall(*_args, **_kwargs):
        stale_provider.shutdown()
        return [{"content": "late memory"}]

    stale_provider.recall = stale_recall
    qdrant_module.format_prefetch = lambda _rows: "must not publish"
    stale_provider.queue_prefetch("stale question")
    qdrant_module.format_prefetch = original_format_prefetch
    assert stale_provider.prefetch("ignored") == ""
    assert stale_provider._closed

    switched_provider = plugin.QdrantMemoryProvider()
    switched_provider._initialized = True
    switched_provider._session_id = "old-session"
    switched_provider._config = {"retrieval": {"mode": "vector", "top_k": 5}}
    switched_provider._store = types.SimpleNamespace(
        next_turn_index=lambda session_id: 0
    )

    def switched_recall(*_args, **_kwargs):
        switched_provider.on_session_switch("new-session")
        return [{"content": "old-session memory"}]

    switched_provider.recall = switched_recall
    qdrant_module.format_prefetch = lambda _rows: "must not cross sessions"
    switched_provider.queue_prefetch("old-session question", session_id="old-session")
    qdrant_module.format_prefetch = original_format_prefetch
    assert switched_provider._session_id == "new-session"
    assert switched_provider.prefetch("ignored", session_id="new-session") == ""

    close_events = []
    closing_provider = plugin.QdrantMemoryProvider()
    closing_provider._store = types.SimpleNamespace(close=lambda: close_events.append("store"))
    closing_provider._embedder = types.SimpleNamespace(
        close=lambda: close_events.append("embedder")
    )
    closing_provider.shutdown()
    assert close_events == ["store", "embedder"]

    closed_store = store_module.QdrantStore(
        "/nonexistent",
        Embedder(),
        connection_cfg={"mode": "remote"},
        collection="assistant",
    )
    closed_store._client = types.SimpleNamespace(close=lambda: close_events.append("client"))
    closed_store.close()
    assert close_events[-1] == "client"
    try:
        _ = closed_store.client
    except RuntimeError as exc:
        assert "closed" in str(exc)
    else:
        raise AssertionError("closed Qdrant store lazily reopened its client")
    qdrant_source = (root / "src/qdrant.py").read_text()
    assert ".enqueue(" not in qdrant_source
    assert "queue.Queue" not in (root / "src/store.py").read_text()
    assert "threading.Thread" not in qdrant_source

if __name__ == "__main__":
    main()
