# Purpose: Sherlock - read-only database query tool for AI assistants
# Dependencies: AI source catalog and prebuilt release archives
# Packages: sherlock-db
_final: prev:

let
  source = (import ../../packages/source-catalog.nix "ai").sherlock-db;
  inherit (source) version;

  srcs = {
    aarch64-darwin = source.source.args;
    x86_64-linux = source.artifacts.x86_64-linux.args;
  };

  platformSrc = srcs.${prev.stdenv.hostPlatform.system} or null;

  skillMd = prev.writeText "SKILL.md" ''
    ---
    name: sherlock
    description: Allows read-only access to SQL databases and Redis for querying and analysis using natural language
    allowed-tools:
       - Bash(~/.claude/skills/sherlock/sherlock:*)
       - Bash(security find-generic-password:*)
    ---

    # Sherlock

    Read-only database access for SQL and Redis. Binary: `~/.claude/skills/sherlock/sherlock`

    ## Ad Hoc Connections (`--url`)

    Use `--url` (`-u`) to connect directly via a database URL without any config file setup. This is ideal when a project has a `DATABASE_URL` in its `.env` file.

    ```bash
    sherlock -u "postgres://user:pass@localhost:5432/mydb" tables
    sherlock -u "mysql://user:pass@localhost:3306/mydb" query "SELECT 1"
    sherlock -u "redis://localhost:6379" info
    ```

    - `--url` and `-c` are mutually exclusive — use one or the other
    - Database type is auto-detected from the URL prefix (`postgres://`, `mysql://`, `sqlite://`, `redis://`)
    - Schema caching and introspection work normally (cached under a synthetic name derived from the URL)
    - Query logging is disabled for ad hoc connections

    **When to use `--url` vs `-c`:** Use `--url` for quick one-off access, especially when the project already has a `DATABASE_URL`. Use `-c` for repeated access to the same database with config-managed credentials.

    ## SSL Connections

    Sherlock 1.4.0 does not pass configured SSL options through `-c`. For a
    server that requires encryption, use `-u` with the database driver's SSL
    query parameters and take care not to log the credential-bearing URL.

    Always use `-f markdown` for human-readable output in conversation.

    ## SQL Commands

    All SQL commands require `-c <connection>` or `-u <url>`. Output is JSON by default; use `-f markdown` for tables.

    ```bash
    sherlock connections                    # List configured connection names
    sherlock -c <conn> tables               # List tables
    sherlock -c <conn> describe <table>     # Table schema
    sherlock -c <conn> introspect           # Full schema (cached)
    sherlock -c <conn> introspect --refresh # Refresh cached schema
    sherlock -c <conn> query "SELECT ..."   # Execute read-only query
    sherlock -c <conn> sample <table> -n 10 # Random sample rows
    sherlock -c <conn> stats <table>        # Data profiling (nulls, distinct counts)
    sherlock -c <conn> indexes <table>      # Table indexes
    sherlock -c <conn> fk <table>           # Foreign key relationships
    ```

    ## Redis Commands

    All Redis commands require `-c <connection>` pointing to a Redis connection.

    ```bash
    sherlock -c <conn> info                 # Server info, memory, keyspace
    sherlock -c <conn> info --section memory # Specific INFO section
    sherlock -c <conn> keys "user:*"        # Scan for keys matching pattern
    sherlock -c <conn> keys --limit 50      # Limit number of results
    sherlock -c <conn> get <key>            # Get value (auto-detects type)
    sherlock -c <conn> get <key> --limit 50 # Limit items for lists/sets/zsets
    sherlock -c <conn> inspect <key>        # Key metadata (type, TTL, memory, encoding)
    sherlock -c <conn> slowlog              # Recent slow queries
    sherlock -c <conn> slowlog -n 20        # Last 20 slow log entries
    sherlock -c <conn> command GET mykey    # Execute any read-only Redis command
    ```

    ## Constraints

    - **Read-only**: SQL allows SELECT, SHOW, DESCRIBE, EXPLAIN, WITH only. Redis allows read commands only (GET, HGETALL, SCAN, etc.) — mutations (SET, DEL, HSET, etc.) are blocked.
    - **Connection required**: Specify `-c <connection>` or `-u <url>`; there is no default
    - **Type-aware**: SQL commands only work with SQL connections, Redis commands only work with Redis connections
    - **Quoting**: PostgreSQL/SQLite use `"identifier"`, MySQL uses `` `identifier` ``

    ## SQL Workflow

    1. Run `sherlock -c <conn> tables`; if configured SSL is insufficient, use an explicit URL with the required SSL parameters
    2. Use `tables` or `introspect` to understand schema (introspect is cached per-connection)
    3. Use `fk` to understand table relationships before writing JOINs
    4. Use `sample` to see real data examples before writing queries
    5. Write SQL based on user's question and schema
    6. Execute with `query`, present results clearly

    ## Redis Workflow

    1. Run `connections` to see available connections
    2. Use `info` to understand the Redis instance (version, memory, keyspace)
    3. Use `keys "pattern:*"` to find keys of interest
    4. Use `get <key>` to retrieve values (auto-detects string/hash/list/set/zset)
    5. Use `inspect <key>` for metadata (TTL, memory usage, encoding)
    6. Use `command` for any other read-only operation

    ## Tips

    - Always use LIMIT to avoid large result sets
    - Use `stats` for SQL data profiling (row counts, null counts, distinct values)
    - Use `-f markdown` for human-readable table output
    - For Redis, use `keys` with specific patterns rather than `*` on large databases
    - Use `--no-types` with `keys` for faster scanning when type info isn't needed
    - Config: `~/.config/sherlock/config.json`
  '';

in
assert source.source.fetcher == "fetchurl";
assert source.artifacts.x86_64-linux.fetcher == "fetchurl";
prev.lib.optionalAttrs (platformSrc != null) {

  sherlock-db = prev.stdenv.mkDerivation {
    pname = "sherlock-db";
    inherit version;

    src = prev.fetchurl platformSrc;

    dontUnpack = true;

    nativeBuildInputs = prev.lib.optionals prev.stdenv.isLinux [
      prev.autoPatchelfHook
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/share/sherlock
      cp $src $out/bin/sherlock
      chmod +x $out/bin/sherlock
      cp ${skillMd} $out/share/sherlock/SKILL.md

      runHook postInstall
    '';

    meta = with prev.lib; {
      description = "Read-only database query tool for AI assistants (PostgreSQL, MySQL, SQLite, Redis)";
      homepage = "https://github.com/michaelbromley/sherlock";
      license = licenses.mit;
      mainProgram = "sherlock";
      sourceProvenance = [ sourceTypes.binaryNativeCode ];
      platforms = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
    };
  };

}
