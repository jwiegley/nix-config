#!/usr/bin/env python3
"""MCP server exposing read-only views of the org PostgreSQL database.

The server is a stdio child of Hermes and provides two tools:

  * ``org_sql``    — direct, sanitized SELECT queries via psycopg2.
  * ``org_search`` — semantic search by shelling out to the ``org`` CLI,
    mirroring the read-only service deployed for Hermes on Vulcan.

Both tools use the dedicated read-only database role. ``org_sql`` rejects
anything that is not a single bare SELECT, denies known SELECT-callable
side-effect functions, and runs in a read-only transaction with bounded
execution and lock waits. The role's server-side EXECUTE grants remain the
authority for extension or user-defined functions. The server never prints or
returns the PGPASSWORD value.

Environment variables (PostgreSQL — psycopg2 reads these via libpq):
  PGHOST       default: 127.0.0.1
  PGPORT       default: 5432
  PGDATABASE   default: org
  PGUSER       default: openclaw
  PGPASSWORD   no default — supplied by the caller's environment

Environment variables (semantic search — org CLI):
  ORG_CONFIG          default: ${HOME}/.config/org/config.yaml
  ORG_DB_BASE_URL     default: http://127.0.0.1:8000 (host LLM gateway)
  ORG_DB_MODEL        default: bge-m3-mlx-fp16 (embedding model)
  The local oMLX endpoint is passed the non-secret API-key sentinel ``unused``.

The ``org`` binary (pkgs.org-jw) is expected on PATH via its wrapper.
"""

import json
import os
import re
import selectors
import shutil
import subprocess
import threading
import time
from typing import Any

import psycopg2
from mcp.server.fastmcp import FastMCP

# -- PostgreSQL connection parameters --------------------------------------
# psycopg2/libpq already honors PG* env vars, but we read them explicitly so
# the service defaults and so we can pass an explicit dict to psycopg2.connect().
PGHOST = os.getenv("PGHOST", "127.0.0.1")
PGPORT = os.getenv("PGPORT", "5432")
PGDATABASE = os.getenv("PGDATABASE", "org")
PGUSER = os.getenv("PGUSER", "openclaw")
# PGPASSWORD is intentionally NOT echoed anywhere. We pull it from the env at
# connect time only and never include it in tool output or error messages.

# -- Semantic-search (org CLI) parameters ----------------------------------
ORG_CONFIG = os.getenv(
    "ORG_CONFIG", os.path.expanduser("~/.config/org/config.yaml")
)
ORG_DB_BASE_URL = os.getenv("ORG_DB_BASE_URL", "http://127.0.0.1:8000")
ORG_DB_MODEL = os.getenv("ORG_DB_MODEL", "bge-m3-mlx-fp16")
SEARCH_TIMEOUT_S = float(os.getenv("ORG_DB_TIMEOUT_S", "60"))
SEARCH_ENVIRONMENT_KEYS = (
    "HOME",
    "LANG",
    "LC_ALL",
    "LC_CTYPE",
    "LOGNAME",
    "NIX_SSL_CERT_FILE",
    "PGDATABASE",
    "PGHOST",
    "PGPASSWORD",
    "PGPORT",
    "PGSSLMODE",
    "PGSSLROOTCERT",
    "PGUSER",
    "SSL_CERT_FILE",
    "TMPDIR",
    "TZ",
    "USER",
)

# These limits are also forced through libpq's connection options, so they are
# active before the first statement and cannot be weakened by a query.
STATEMENT_TIMEOUT_MS = 15_000
LOCK_TIMEOUT_MS = 5_000
MAX_RESULT_BYTES = 1_000_000
MAX_ROW_BYTES = MAX_RESULT_BYTES
MAX_SEARCH_QUERY_BYTES = 64 * 1024
QUERY_WALL_TIMEOUT_S = 15.0

# Statement-level keywords that mutate state or escape the single-SELECT
# contract. A query containing any of these as a standalone word is rejected
# outright — this is a coarse but deliberately conservative guard, layered on
# top of the "must start with SELECT" and "no semicolon" checks below.
FORBIDDEN_FUNCTIONS = frozenset(
    {
        "nextval",
        "pg_cancel_backend",
        "pg_notify",
        "pg_sleep",
        "pg_sleep_for",
        "pg_sleep_until",
        "pg_terminate_backend",
        "set_config",
        "setval",
    }
)
FORBIDDEN_KEYWORDS = frozenset(
    {
        "insert",
        "update",
        "delete",
        "drop",
        "alter",
        "create",
        "truncate",
        "grant",
        "revoke",
        "copy",
        "call",
        "do",
        "merge",
        "replace",
        "vacuum",
        "analyze",
        "reindex",
        "cluster",
        "comment",
        "set",
        "reset",
        "begin",
        "commit",
        "rollback",
        "savepoint",
        "lock",
        "execute",
        "prepare",
        "deallocate",
        "listen",
        "notify",
        "refresh",
        "import",
        "load",
        "security",  # guards against "SECURITY LABEL"
        # Explicitly reject PostgreSQL's intentional delay functions. The
        # server-side statement timeout remains the general availability bound
        # for other SELECT-callable functions.
    }
) | FORBIDDEN_FUNCTIONS

_DOLLAR_QUOTE_RE = re.compile(r"\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$")


def _err(msg: str) -> str:
    return json.dumps({"error": msg})


def _mask_sql_noncode(
    sql: str,
) -> tuple[str, list[tuple[str, int]], str | None]:
    """Mask comments and literal bodies without changing character offsets.

    The returned text is used only for structural validation. The database
    receives the original query bytes, minus one validated trailing statement
    terminator. Quoted identifiers are also masked, but returned separately so
    explicitly denied function calls remain detectable when quoted.
    """
    masked = list(sql)
    quoted_identifiers: list[tuple[str, int]] = []
    length = len(sql)
    index = 0

    def blank(start: int, end: int) -> None:
        for offset in range(start, end):
            if masked[offset] != "\n":
                masked[offset] = " "

    while index < length:
        if sql.startswith("--", index):
            end = sql.find("\n", index + 2)
            if end < 0:
                end = length
            blank(index, end)
            index = end
            continue

        if sql.startswith("/*", index):
            start = index
            index += 2
            depth = 1
            while index < length and depth:
                if sql.startswith("/*", index):
                    depth += 1
                    index += 2
                elif sql.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
            if depth:
                return "", [], "query contains an unterminated block comment"
            blank(start, index)
            continue

        if sql[index] == "'":
            start = index
            escape_string = (
                index > 0
                and sql[index - 1] in "eE"
                and (index == 1 or not (sql[index - 2].isalnum() or sql[index - 2] == "_"))
            )
            index += 1
            while index < length:
                if escape_string and sql[index] == "\\":
                    index = min(length, index + 2)
                    continue
                if sql[index] == "'":
                    if index + 1 < length and sql[index + 1] == "'":
                        index += 2
                        continue
                    index += 1
                    break
                index += 1
            else:
                return "", [], "query contains an unterminated string literal"
            blank(start, index)
            continue

        if sql[index] == '"':
            start = index
            identifier: list[str] = []
            index += 1
            while index < length:
                if sql[index] == '"':
                    if index + 1 < length and sql[index + 1] == '"':
                        identifier.append('"')
                        index += 2
                        continue
                    index += 1
                    break
                identifier.append(sql[index])
                index += 1
            else:
                return "", [], "query contains an unterminated quoted identifier"
            blank(start, index)
            quoted_identifiers.append(("".join(identifier).lower(), index))
            continue

        if sql[index] == "$" and (
            index == 0 or not (sql[index - 1].isalnum() or sql[index - 1] in "_$")
        ):
            match = _DOLLAR_QUOTE_RE.match(sql, index)
            if match is not None:
                delimiter = match.group(0)
                end = sql.find(delimiter, match.end())
                if end < 0:
                    return "", [], "query contains an unterminated dollar-quoted literal"
                end += len(delimiter)
                blank(index, end)
                index = end
                continue

        index += 1

    return "".join(masked), quoted_identifiers, None


def _prepare_select(query: str) -> tuple[str | None, str | None]:
    """Return ``(error, original_query_without_trailing_terminator)``."""
    masked, quoted_identifiers, lexical_error = _mask_sql_noncode(query)
    if lexical_error is not None:
        return lexical_error, None

    semicolons = [index for index, char in enumerate(masked) if char == ";"]
    if semicolons:
        terminator = semicolons[0]
        if len(semicolons) != 1 or masked[terminator + 1 :].strip():
            return "only a single statement is allowed (no ';'-chained statements)", None
        statement_masked = masked[:terminator].strip()
        executable = query[:terminator].rstrip()
    else:
        statement_masked = masked.strip()
        executable = query.rstrip()

    if not statement_masked:
        return "query is empty", None
    lowered = statement_masked.lower()
    if re.match(r"^(select|with)\b", lowered) is None:
        return "query must be a single read-only SELECT (or WITH ... SELECT)", None

    tokens = set(re.findall(r"[a-z_]+", lowered))
    hit = tokens & FORBIDDEN_KEYWORDS
    hit.update(
        token
        for token in tokens
        if token.startswith(("pg_advisory_", "pg_try_advisory_"))
        and "lock" in token
    )
    for identifier, end in quoted_identifiers:
        next_code = end
        while next_code < len(masked) and masked[next_code].isspace():
            next_code += 1
        if next_code < len(masked) and masked[next_code] == "(" and (
            identifier in FORBIDDEN_FUNCTIONS
            or (
                identifier.startswith(("pg_advisory_", "pg_try_advisory_"))
                and "lock" in identifier
            )
        ):
            hit.add(identifier)
    if hit:
        return f"query contains forbidden keyword(s): {sorted(hit)}", None

    return None, executable


def _validate_select(query: str) -> str | None:
    """Return None if ``query`` is a single read-only SELECT, else an error.

    The contract is deliberately strict:
      * exactly one statement (no semicolon-chaining; a single trailing
        semicolon is tolerated and trimmed),
      * the statement must begin with SELECT (or a leading WITH ... that
        feeds a SELECT — common-table-expression read queries),
      * no statement-mutating keyword appears as a standalone token.
    """
    return _prepare_select(query)[0]


def _rows_to_markdown(columns: list[str], rows: list[tuple[Any, ...]]) -> str:
    """Render a result set as a GitHub-flavored Markdown table.

    Cell values are stringified and pipe characters escaped so the table
    stays well-formed. An empty result set returns just the header row.
    """

    def cell(value: Any) -> str:
        if value is None:
            return ""
        return str(value).replace("|", "\\|").replace("\n", " ")

    lines = [
        "| " + " | ".join(columns) + " |",
        "| " + " | ".join("---" for _ in columns) + " |",
    ]
    used = sum(len(line.encode("utf-8")) for line in lines) + 1
    for row in rows:
        line = "| " + " | ".join(cell(v) for v in row) + " |"
        used += len(line.encode("utf-8")) + 1
        if used > MAX_RESULT_BYTES:
            return _err(
                f"query output exceeds the {MAX_RESULT_BYTES}-byte response limit"
            )
        lines.append(line)
    return "\n".join(lines)


mcp = FastMCP("org-db")


class _JsonObjectPairs(list[tuple[str, Any]]):
    """Distinguish JSON objects from arrays while preserving duplicate keys."""


class _JsonNumber(str):
    """Keep an exact JSON numeric lexeme without quoting it inside containers."""

    def __repr__(self) -> str:
        return str(self)


def _decode_json_row(payload: bytes, transfer_limit: int) -> list[tuple[str, Any]]:
    if len(payload) > transfer_limit:
        raise OverflowError

    decoded = json.loads(
        payload.decode("utf-8"),
        parse_float=_JsonNumber,
        parse_int=_JsonNumber,
        object_pairs_hook=_JsonObjectPairs,
    )
    if not isinstance(decoded, _JsonObjectPairs) or not all(
        isinstance(name, str) for name, _value in decoded
    ):
        raise ValueError("row JSON is not an object")

    def restore(value: Any) -> Any:
        if isinstance(value, _JsonObjectPairs):
            return {name: restore(nested) for name, nested in value}
        if isinstance(value, list):
            return [restore(nested) for nested in value]
        return value

    return [(name, restore(value)) for name, value in decoded]


class _QueryWallTimeout(TimeoutError):
    pass


@mcp.tool()
def org_sql(query: str, limit: int = 100) -> str:
    """Run a READ-ONLY SQL SELECT against the org PostgreSQL database.

    Use this when you know the schema and want exact rows — e.g. to list
    headings, tags, or properties from the org store. For fuzzy/semantic
    lookup ("find notes about X"), prefer ``org_search``.

    SECURITY: only a single bare ``SELECT`` (or ``WITH ... SELECT``) is
    permitted. Semicolon-chained statements, mutating keywords, and known
    SELECT-callable side-effect functions are rejected before the query reaches
    the database. The dedicated role's EXECUTE grants are the final boundary
    for extension or user-defined functions.

    Args:
      query: a single read-only SELECT statement. A lone trailing semicolon
        is tolerated; multiple statements are not.
      limit: maximum rows to return (1–1000). Default 100. Applied as an
        outer ``LIMIT`` so it is enforced even if the query omits one.

    Returns a Markdown table of the result rows, or a JSON ``{"error": ...}``
    object on validation/connection failure. The PGPASSWORD value is never
    included in any output.
    """
    if limit < 1 or limit > 1000:
        return _err("limit must be between 1 and 1000")

    bad, inner = _prepare_select(query)
    if bad is not None:
        return _err(bad)
    assert inner is not None
    # Execute the user's SELECT exactly once through a one-row server cursor.
    # PostgreSQL caps every row before libpq sees it, and the renderer enforces
    # the aggregate response cap. A connection watchdog covers the whole cursor
    # lifetime because statement_timeout applies separately to each FETCH.
    wrapped = (
        "WITH org_sql_input AS MATERIALIZED ("
        f"SELECT * FROM (\n{inner}\n) AS org_sql_sub LIMIT {limit}"
        ") "
        "SELECT substring("
        "convert_to(row_to_json(org_sql_input)::text, 'UTF8') "
        f"FROM 1 FOR {MAX_ROW_BYTES + 1}) AS row_json "
        "FROM org_sql_input"
    )

    conn = None
    watchdog = None
    wall_timeout_reached = threading.Event()
    try:
        # psycopg2 reads PGPASSWORD from the environment via libpq; we never
        # name the password in code or output.
        conn = psycopg2.connect(
            host=PGHOST,
            port=PGPORT,
            dbname=PGDATABASE,
            user=PGUSER,
            connect_timeout=5,
            options=(
                f"-c default_transaction_read_only=on "
                f"-c statement_timeout={STATEMENT_TIMEOUT_MS} "
                f"-c lock_timeout={LOCK_TIMEOUT_MS}"
            ),
        )
        # Defense in depth: mark the whole transaction read-only so the
        # backend itself rejects any write that slipped past our parser.
        conn.set_session(readonly=True, autocommit=False)

        def cancel_at_deadline() -> None:
            wall_timeout_reached.set()
            try:
                conn.cancel()
            except Exception:  # noqa: BLE001 — best-effort cancellation only
                pass

        watchdog = threading.Timer(QUERY_WALL_TIMEOUT_S, cancel_at_deadline)
        watchdog.daemon = True
        watchdog.start()

        with conn.cursor(name="org_sql_stream") as cur:
            cur.itersize = 1
            cur.execute(wrapped)
            first_batch = cur.fetchmany(1)
            if wall_timeout_reached.is_set():
                raise _QueryWallTimeout
            if not first_batch:
                rendered = "(no rows)"
            else:
                first = _decode_json_row(bytes(first_batch[0][0]), MAX_ROW_BYTES)
                columns = [name for name, _value in first]

                def rows():
                    yield tuple(value for _name, value in first)
                    while True:
                        if wall_timeout_reached.is_set():
                            raise _QueryWallTimeout
                        batch = cur.fetchmany(1)
                        if wall_timeout_reached.is_set():
                            raise _QueryWallTimeout
                        if not batch:
                            return
                        decoded = _decode_json_row(bytes(batch[0][0]), MAX_ROW_BYTES)
                        if [name for name, _value in decoded] != columns:
                            raise ValueError("row shape changed")
                        yield tuple(value for _name, value in decoded)

                rendered = _rows_to_markdown(columns, rows())
        conn.rollback()
    except OverflowError:
        if conn is not None:
            conn.rollback()
        return _err(
            f"query contains a row larger than the {MAX_ROW_BYTES}-byte transfer limit"
        )
    except _QueryWallTimeout:
        if conn is not None:
            conn.rollback()
        return _err(
            f"database query exceeded the {QUERY_WALL_TIMEOUT_S:g}-second wall-clock limit"
        )
    except psycopg2.Error:
        # PostgreSQL diagnostics can quote statement fragments and row values;
        # keep the tool response stable and non-sensitive.
        if wall_timeout_reached.is_set():
            return _err(
                f"database query exceeded the {QUERY_WALL_TIMEOUT_S:g}-second wall-clock limit"
            )
        return _err("database query failed")
    except Exception:  # noqa: BLE001 — keep runtime details out of tool output
        return _err("query failed")
    finally:
        if watchdog is not None:
            watchdog.cancel()
            watchdog.join(timeout=1)
        if conn is not None:
            conn.close()

    return rendered


class _SearchOutputTooLarge(RuntimeError):
    pass


def _terminate_search(proc: subprocess.Popen[bytes]) -> None:
    if proc.poll() is None:
        proc.kill()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass


def _run_search(cmd: list[str], query: bytes) -> tuple[int, bytes]:
    """Run org with query on stdin and a hard stdout/time bound."""
    child_environment = {
        name: os.environ[name]
        for name in SEARCH_ENVIRONMENT_KEYS
        if name in os.environ
    }
    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=0,
        env=child_environment,
    )
    assert proc.stdin is not None and proc.stdout is not None
    selector = selectors.DefaultSelector()
    input_fd = proc.stdin.fileno()
    output_fd = proc.stdout.fileno()
    os.set_blocking(input_fd, False)
    os.set_blocking(output_fd, False)
    selector.register(input_fd, selectors.EVENT_WRITE, "stdin")
    selector.register(output_fd, selectors.EVENT_READ, "stdout")
    offset = 0
    output = bytearray()
    stdout_open = True
    deadline = time.monotonic() + SEARCH_TIMEOUT_S

    try:
        while stdout_open:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(cmd, SEARCH_TIMEOUT_S)
            ready = selector.select(remaining)
            if not ready:
                raise subprocess.TimeoutExpired(cmd, SEARCH_TIMEOUT_S)
            for key, _events in ready:
                if key.data == "stdin":
                    try:
                        written = os.write(input_fd, query[offset:])
                    except BrokenPipeError:
                        written = 0
                        offset = len(query)
                    except BlockingIOError:
                        continue
                    offset += written
                    if offset >= len(query):
                        selector.unregister(input_fd)
                        proc.stdin.close()
                else:
                    try:
                        chunk = os.read(output_fd, 64 * 1024)
                    except BlockingIOError:
                        continue
                    if not chunk:
                        selector.unregister(output_fd)
                        proc.stdout.close()
                        stdout_open = False
                        continue
                    output.extend(chunk)
                    if len(output) > MAX_RESULT_BYTES:
                        raise _SearchOutputTooLarge

        remaining = max(0.001, deadline - time.monotonic())
        return proc.wait(timeout=remaining), bytes(output)
    except BaseException:
        _terminate_search(proc)
        raise
    finally:
        selector.close()
        if proc.stdin is not None and not proc.stdin.closed:
            proc.stdin.close()
        if proc.stdout is not None and not proc.stdout.closed:
            proc.stdout.close()


@mcp.tool()
def org_search(query: str, n: int = 10) -> str:
    """Semantic search over the org database via embeddings.

    Shells out to the ``org`` CLI: it embeds the query through the configured
    OpenAI-compatible endpoint and returns the nearest org entries. Use
    this for natural-language lookup ("notes about the pool heater") where
    you don't know the exact schema or wording.

    Args:
      query: free-text search terms.
      n: number of nearest results to return (1–50). Default 10.

    Returns the raw ``org db search`` output, or a JSON ``{"error": ...}``
    object on failure. The local endpoint uses a fixed, non-secret API-key
    sentinel because the CLI requires the argument syntactically.
    """
    if not query.strip():
        return _err("query is empty")
    if n < 1 or n > 50:
        return _err("n must be between 1 and 50")

    org_executable = shutil.which("org")
    if org_executable is None:
        return _err("the 'org' CLI is not on PATH")

    encoded_query = query.encode("utf-8")
    if len(encoded_query) > MAX_SEARCH_QUERY_BYTES:
        return _err(
            f"query exceeds the {MAX_SEARCH_QUERY_BYTES}-byte search input limit"
        )

    cmd = [
        org_executable,
        "-c",
        ORG_CONFIG,
        "db",
        "search",
        "--base-url",
        ORG_DB_BASE_URL,
        "-m",
        ORG_DB_MODEL,
        "--api-key",
        "unused",
        "--query-stdin",
        "-n",
        str(n),
    ]

    try:
        returncode, stdout = _run_search(cmd, encoded_query)
    except subprocess.TimeoutExpired:
        return _err(f"org db search timed out after {SEARCH_TIMEOUT_S}s")
    except _SearchOutputTooLarge:
        return _err(
            f"org db search output exceeds the {MAX_RESULT_BYTES}-byte response limit"
        )
    except OSError:
        return _err("failed to invoke org")

    if returncode != 0:
        # Never surface arbitrary child diagnostics: they may include a query,
        # path, endpoint, or future credential-bearing error.
        return _err(f"org db search exited {returncode}")

    return stdout.decode("utf-8", errors="replace")


if __name__ == "__main__":
    mcp.run()
