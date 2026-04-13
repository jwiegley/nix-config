# overlays/30-sherlock-db.nix
# Purpose: Sherlock - read-only database query tool for AI assistants
# Dependencies: None (uses pre-built binaries from GitHub releases)
# Packages: sherlock-db
final: prev:

let
  version = "1.3.0";

  srcs = {
    aarch64-darwin = {
      url = "https://github.com/michaelbromley/sherlock/releases/download/v${version}/sherlock-darwin-arm64";
      hash = "sha256-l1dfzfjHDFhM9+Ro8E3jYJgSAYUOn898VUluoqGqKBw=";
    };
    x86_64-linux = {
      url = "https://github.com/michaelbromley/sherlock/releases/download/v${version}/sherlock-linux-x64";
      hash = "sha256-u/XyOTbwZXjTqidkAIhLOs51i/lVRlcHYCm+wv7Di+M=";
    };
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

    ## SSL Connections with Keychain Passwords

    When a PostgreSQL server requires SSL (e.g., `pg_hba.conf` rejects unencrypted connections) and the config uses `$keychain` for the password, the `-c` flag may fail because sherlock does not yet pass SSL options from the config file. Work around this by constructing the URL with the password retrieved from macOS Keychain:

    ```bash
    PW=$(security find-generic-password -a <keychain-account> -w) && \
    sherlock -u "postgres://user:''${PW}@host:5432/db?sslmode=require" <command>
    ```

    The `<keychain-account>` corresponds to the key name in the `"$keychain"` field of the connection config. For example, for a connection configured with `"password": { "$keychain": "org" }`:

    ```bash
    PW=$(security find-generic-password -a org -w) && \
    sherlock -u "postgres://johnw:''${PW}@postgres.vulcan.lan:5432/org?sslmode=require" query "SELECT ..." -f markdown
    ```

    Always use `-f markdown` for human-readable output in conversation.

    ## SQL Commands

    All SQL commands require `-c <connection>` or `-u <url>`. Output is JSON by default, use `-f markdown` for tables.

    ```bash
    sherlock connections                    # List available connections
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
    - **Connection required**: Always specify `-c <connection>` or `-u <url>` (no default)
    - **Type-aware**: SQL commands only work with SQL connections, Redis commands only work with Redis connections
    - **Quoting**: PostgreSQL/SQLite use `"identifier"`, MySQL uses `` `identifier` ``

    ## SQL Workflow

    1. Try `sherlock -c <conn> tables` first. If it fails with an SSL/encryption error, switch to the URL+Keychain approach described above
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
      maintainers = with maintainers; [ jwiegley ];
    };
  };

}
