#!/usr/bin/env python3
"""Behavioral contract for the read-only Org database MCP server."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def load_server(path: Path):
    spec = importlib.util.spec_from_file_location("hermes_org_db_mcp", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def main() -> None:
    source = Path(sys.argv[1]).resolve()
    executable = Path(sys.argv[2]).resolve()
    org_executable = Path(sys.argv[3]).resolve()
    server = load_server(source)

    help_result = subprocess.run(
        [str(org_executable), "db", "search", "--help"],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    assert help_result.returncode == 0
    assert "--query-stdin" in help_result.stdout

    assert server._validate_select("SELECT 1") is None
    assert server._validate_select("WITH x AS (SELECT 1) SELECT * FROM x") is None
    assert server._validate_select("SELECT 1; -- one trailing terminator") is None
    assert server._validate_select("SELECT 'update' AS ordinary_text") is None
    assert server._validate_select("SELECT 'a;b' AS ordinary_text") is None
    assert server._validate_select("SELECT 'https://host.test/a--b' AS ordinary_text") is None
    assert server._validate_select("SELECT $$delete; -- still text$$ AS ordinary_text") is None
    assert server._validate_select('SELECT "update" FROM headings') is None
    assert server._validate_select("UPDATE notes SET title = 'wrong'") is not None
    assert server._validate_select("WITH x AS (DELETE FROM notes RETURNING *) SELECT * FROM x") is not None
    assert server._validate_select("SELECT 1; DELETE FROM notes") is not None
    assert server._validate_select("SELECT pg_sleep(600)") is not None
    assert server._validate_select("SELECT pg_sleep_for(interval '10 minutes')") is not None
    assert (
        server._validate_select("SELECT set_config('statement_timeout', '0', false)")
        is not None
    )
    for effectful_query in [
        "SELECT pg_terminate_backend(42)",
        "SELECT pg_cancel_backend(42)",
        "SELECT pg_advisory_lock(42)",
        "SELECT pg_try_advisory_xact_lock(42)",
        "SELECT nextval('headings_id_seq')",
        "SELECT setval('headings_id_seq', 42)",
        "SELECT pg_notify('channel', 'payload')",
    ]:
        assert server._validate_select(effectful_query) is not None

    events = []

    class Cursor:
        def __init__(self, name, rows, delay=0):
            self.name = name
            self.itersize = None
            self.rows = list(rows)
            self.delay = delay

        def __enter__(self):
            return self

        def __exit__(self, *_exc):
            return False

        def execute(self, statement, parameters=None):
            events.append(("execute", self.name, statement, parameters))

        def fetchmany(self, limit):
            events.append(("fetchmany", self.name, limit))
            if self.delay:
                time.sleep(self.delay)
            if not self.rows:
                return []
            return [self.rows.pop(0)]

    class Connection:
        def __init__(self, rows, delay=0):
            self.rows = rows
            self.delay = delay

        def set_session(self, **kwargs):
            events.append(("set_session", kwargs))

        def cursor(self, name=None):
            events.append(("cursor", name))
            return Cursor(name, self.rows, self.delay)

        def cancel(self):
            events.append(("cancel",))

        def rollback(self):
            events.append(("rollback",))

        def close(self):
            events.append(("close",))

    original_connect = server.psycopg2.connect
    server.psycopg2.connect = lambda **kwargs: (
        events.append(("connect", kwargs))
        or Connection(
            [
                (
                    b'{"amount":12345678901234567890.12345678901234567890,'
                    b'"x":1,"x":2,"meta":{"enabled":true},"empty":{},'
                    b'"items":[{"n":3}],"pct":"100%"}',
                )
            ]
        )
    )
    table = server.org_sql(
        "SELECT amount, left_value AS x, right_value AS x, '100%' AS pct "
        "FROM headings",
        limit=7,
    )
    server.psycopg2.connect = original_connect
    assert table == (
        "| amount | x | x | meta | empty | items | pct |\n"
        "| --- | --- | --- | --- | --- | --- | --- |\n"
        "| 12345678901234567890.12345678901234567890 | 1 | 2 | "
        "{'enabled': True} | {} | [{'n': 3}] | 100% |"
    )
    assert (
        "set_session",
        {
            "readonly": True,
            "autocommit": False,
        },
    ) in events
    connect = next(event for event in events if event[0] == "connect")
    assert connect[1]["connect_timeout"] == 5
    assert connect[1]["options"] == (
        "-c default_transaction_read_only=on "
        "-c statement_timeout=15000 -c lock_timeout=5000"
    )
    execute_events = [event for event in events if event[0] == "execute"]
    assert len(execute_events) == 1
    stream_execute = execute_events[0]
    assert stream_execute[1] == "org_sql_stream"
    assert stream_execute[3] is None
    assert "LIMIT 7" in stream_execute[2]
    assert f"FOR {server.MAX_ROW_BYTES + 1}" in stream_execute[2]
    assert "100%" in stream_execute[2]
    assert "WITH org_sql_input AS MATERIALIZED" in stream_execute[2]
    assert "row_to_json(org_sql_input)" in stream_execute[2]
    assert "substring(" in stream_execute[2]
    assert ("fetchmany", "org_sql_stream", 1) in events
    assert ("rollback",) in events and ("close",) in events

    events.clear()
    server.psycopg2.connect = lambda **_kwargs: Connection(
        [(b"x" * (server.MAX_ROW_BYTES + 1),)]
    )
    oversized_row = json.loads(server.org_sql("SELECT giant_value FROM headings"))
    server.psycopg2.connect = original_connect
    assert oversized_row == {
        "error": (
            f"query contains a row larger than the {server.MAX_ROW_BYTES}-byte transfer limit"
        )
    }
    assert [event[0] for event in events].count("execute") == 1
    assert ("rollback",) in events and ("close",) in events

    original_wall_timeout = server.QUERY_WALL_TIMEOUT_S
    events.clear()
    server.QUERY_WALL_TIMEOUT_S = 0.02
    server.psycopg2.connect = lambda **_kwargs: Connection(
        [(b'{"heading":"too slow"}',)], delay=0.08
    )
    started = time.monotonic()
    wall_timeout = json.loads(server.org_sql("SELECT heading FROM headings"))
    server.psycopg2.connect = original_connect
    server.QUERY_WALL_TIMEOUT_S = original_wall_timeout
    assert wall_timeout == {
        "error": "database query exceeded the 0.02-second wall-clock limit"
    }
    assert time.monotonic() - started < 0.5
    assert ("cancel",) in events

    oversized = "x" * server.MAX_RESULT_BYTES
    rendered = json.loads(server._rows_to_markdown(["value"], [(oversized,)]))
    assert rendered == {
        "error": f"query output exceeds the {server.MAX_RESULT_BYTES}-byte response limit"
    }

    original_which = server.shutil.which
    original_timeout = server.SEARCH_TIMEOUT_S
    original_org_config = server.ORG_CONFIG
    with tempfile.TemporaryDirectory(prefix="hermes-org-search-contract-") as directory:
        root = Path(directory)
        fake_org = root / "org"
        config_path = root / "config.yaml"
        capture = root / "config.yaml.capture"
        fake_org.write_text(
            f"""#!{sys.executable}
import json
import os
import sys
import time

query = sys.stdin.read()
config_path = sys.argv[sys.argv.index("-c") + 1]
with open(config_path + ".capture", "w", encoding="utf-8") as handle:
    json.dump({{"argv": sys.argv, "stdin": query, "environment": dict(os.environ)}}, handle)
if query == "oversized":
    sys.stdout.write("x" * 1000001)
    sys.stdout.flush()
    time.sleep(30)
elif query == "failure":
    sys.stderr.write("secret-bearing child diagnostic")
    raise SystemExit(7)
elif query == "timeout":
    time.sleep(30)
else:
    sys.stdout.write("result")
""",
            encoding="utf-8",
        )
        fake_org.chmod(0o755)
        server.shutil.which = lambda _name: str(fake_org)
        server.ORG_CONFIG = str(config_path)
        os.environ["OPENROUTER_API_KEY"] = "must-not-appear-in-argv"
        os.environ["ANTHROPIC_API_KEY"] = "must-not-reach-child"
        os.environ["PGPASSWORD"] = "expected-db-child-secret"

        sensitive_query = "pool heater token=must-stay-on-stdin"
        assert server.org_search(sensitive_query, n=4) == "result"
        captured = json.loads(capture.read_text())
        assert sensitive_query not in captured["argv"]
        assert captured["stdin"] == sensitive_query
        assert "--query-stdin" in captured["argv"]
        assert captured["argv"][captured["argv"].index("--api-key") + 1] == "unused"
        assert "must-not-appear-in-argv" not in captured["argv"]
        assert captured["environment"]["PGPASSWORD"] == "expected-db-child-secret"
        assert "OPENROUTER_API_KEY" not in captured["environment"]
        assert "ANTHROPIC_API_KEY" not in captured["environment"]

        server.SEARCH_TIMEOUT_S = 2
        started = time.monotonic()
        assert json.loads(server.org_search("oversized")) == {
            "error": f"org db search output exceeds the {server.MAX_RESULT_BYTES}-byte response limit"
        }
        assert time.monotonic() - started < server.SEARCH_TIMEOUT_S

        failed_search_result = server.org_search("failure")
        assert json.loads(failed_search_result) == {"error": "org db search exited 7"}
        assert "secret-bearing" not in failed_search_result

        server.SEARCH_TIMEOUT_S = 0.1
        timeout_result = json.loads(server.org_search("timeout"))
        assert timeout_result == {"error": "org db search timed out after 0.1s"}

        assert json.loads(server.org_search("x" * (server.MAX_SEARCH_QUERY_BYTES + 1))) == {
            "error": (
                f"query exceeds the {server.MAX_SEARCH_QUERY_BYTES}-byte search input limit"
            )
        }

    server.SEARCH_TIMEOUT_S = original_timeout
    server.ORG_CONFIG = original_org_config
    server.shutil.which = original_which
    for name in [
        "ANTHROPIC_API_KEY",
        "OPENROUTER_API_KEY",
        "PGPASSWORD",
    ]:
        os.environ.pop(name, None)

    requests = [
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-03-26",
                "capabilities": {},
                "clientInfo": {"name": "nix-check", "version": "1"},
            },
        },
        {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
    ]
    process = subprocess.run(
        [str(executable)],
        input="".join(json.dumps(request) + "\n" for request in requests),
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    assert process.returncode == 0, process.stderr
    responses = [json.loads(line) for line in process.stdout.splitlines() if line.strip()]
    tools_response = next(response for response in responses if response.get("id") == 2)
    assert {tool["name"] for tool in tools_response["result"]["tools"]} == {
        "org_search",
        "org_sql",
    }


if __name__ == "__main__":
    main()
