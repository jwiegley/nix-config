{ pkgs }:

let
  inherit (pkgs) lib;
  probe = pkgs.stdenv.mkDerivation {
    pname = "managed-mcp-stdio-probe";
    version = "1";
    src = ./managed-mcp-stdio-probe.c;
    dontUnpack = true;
    strictDeps = true;
    buildPhase = ''
      runHook preBuild
      $CC -std=c11 -Wall -Wextra -Werror -pedantic "$src" -o managed-mcp-stdio-probe
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm0755 managed-mcp-stdio-probe "$out/bin/managed-mcp-stdio-probe"
      runHook postInstall
    '';
  };
  launcher = lib.getExe pkgs.nix-managed-mcp-stdio;
  managedPath = pkgs.nix-managed-mcp-stdio.runtimePath;
  networkGuardedPal = pkgs.writeShellScript "network-guarded-pal-mcp-server" ''
    export PYTHONPATH="''${PAL_NETWORK_GUARD_PATH:?}"
    exec ${lib.getExe pkgs.pal-mcp-server} "$@"
  '';
in
pkgs.runCommand "managed-mcp-stdio-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    work="$TMPDIR/work"
    mkdir -p "$work"
    cd "$work"

    inherited=(
      --inherit ANTHROPIC_API_KEY
      --inherit DEFAULT_MODEL
      --inherit HOME
      --inherit NODE_EXTRA_CA_CERTS
      --inherit OPENAI_API_KEY
    )

    result="$(
      printf '%s\n' input-sentinel | env -i \
        ANTHROPIC_API_KEY=anthropic-sentinel \
        BASH_ENV=/forbidden \
        DEFAULT_MODEL=auto \
        DYLD_INSERT_LIBRARIES= \
        GEMINI_API_KEY=other-provider-sentinel \
        GIT_AI_SOCKET=/forbidden \
        GIT_TRACE2_EVENT=/forbidden \
        HOME=/managed-home \
        LD_PRELOAD= \
        NODE_OPTIONS=--forbidden \
        NODE_EXTRA_CA_CERTS=/managed-node-ca \
        OPENAI_API_KEY=typed-sentinel \
        PATH=/shadowed/path \
        PYTHONPATH=/forbidden \
        SSH_AUTH_SOCK=/forbidden \
        UNRELATED_SECRET=unrelated-sentinel \
        ${launcher} "''${inherited[@]}" -- \
        ${probe}/bin/managed-mcp-stdio-probe \
          present argument-sentinel "$work" ${lib.escapeShellArg managedPath}
    )"
    test "$result" = ok

    result="$(
      printf '%s\n' input-sentinel | env -i \
        DEFAULT_MODEL=auto \
        HOME=/managed-home \
        OPENAI_API_KEY= \
        PATH=/shadowed/path \
        ${launcher} "''${inherited[@]}" -- \
        ${probe}/bin/managed-mcp-stdio-probe \
          absent argument-sentinel "$work" ${lib.escapeShellArg managedPath}
    )"
    test "$result" = ok

    result="$(
      printf '%s\n' input-sentinel | env -i \
        DEFAULT_MODEL=auto \
        GEMINI_API_KEY=other-provider-sentinel \
        HOME=/managed-home \
        PATH=/shadowed/path \
        ${launcher} "''${inherited[@]}" -- \
        ${probe}/bin/managed-mcp-stdio-probe \
          absent argument-sentinel "$work" ${lib.escapeShellArg managedPath}
    )"
    test "$result" = ok

    result="$(
      printf '%s\n' input-sentinel | env -i \
        DEFAULT_MODEL=auto \
        HOME=/managed-home \
        OPENAI_API_KEY='$'"{OPENAI_API_KEY}" \
        PATH=/shadowed/path \
        ${launcher} "''${inherited[@]}" -- \
        ${probe}/bin/managed-mcp-stdio-probe \
          absent argument-sentinel "$work" ${lib.escapeShellArg managedPath}
    )"
    test "$result" = ok

    result="$(
      printf '%s\n' input-sentinel | env -i \
        DEFAULT_MODEL=auto \
        HOME=/managed-home \
        OPENAI_API_KEY='$'"{OPENAI_API_KEY:-}" \
        PATH=/shadowed/path \
        ${launcher} "''${inherited[@]}" -- \
        ${probe}/bin/managed-mcp-stdio-probe \
          absent argument-sentinel "$work" ${lib.escapeShellArg managedPath}
    )"
    test "$result" = ok

    exec 9>"$work/inherited-descriptor"
    result="$(${launcher} -- ${probe}/bin/managed-mcp-stdio-probe fd)"
    exec 9>&-
    test "$result" = ok

    export ANTHROPIC_API_KEY=anthropic-sentinel
    export GEMINI_API_KEY=other-provider-sentinel
    export NODE_EXTRA_CA_CERTS=/managed-node-ca
    export OPENAI_API_KEY=typed-sentinel
    export UNRELATED_SECRET=unrelated-sentinel
    set +e
    env -i HOME=/managed-home PATH=/shadowed/path \
      ${launcher} --inherit HOME -- \
      ${probe}/bin/managed-mcp-stdio-probe exit
    exit_status=$?
    env -i HOME=/managed-home PATH=/shadowed/path \
      ${launcher} --inherit HOME -- \
      ${probe}/bin/managed-mcp-stdio-probe signal 2>/dev/null
    signal_status=$?
    ${launcher} --inherit lowercase -- /bin/true 2>usage.err
    invalid_name_status=$?
    ${launcher} --inherit PATH -- /bin/true 2>>usage.err
    inherited_path_status=$?
    ${launcher} --inherit HOME --inherit HOME -- /bin/true 2>>usage.err
    duplicate_name_status=$?
    ${launcher} --inherit HOME /bin/true 2>>usage.err
    missing_delimiter_status=$?
    ${launcher} --inherit HOME -- 2>>usage.err
    missing_target_status=$?
    ${launcher} -- /relative-target 2>>usage.err
    missing_executable_status=$?
    touch non-executable
    ${launcher} -- "$work/non-executable" 2>>usage.err
    non_executable_status=$?
    ${launcher} -- relative-target 2>>usage.err
    relative_target_status=$?
    set -e

    test "$exit_status" -eq 23
    test "$signal_status" -eq 143
    test "$invalid_name_status" -eq 64
    test "$inherited_path_status" -eq 64
    test "$duplicate_name_status" -eq 64
    test "$missing_delimiter_status" -eq 64
    test "$missing_target_status" -eq 64
    test "$missing_executable_status" -eq 127
    test "$non_executable_status" -eq 126
    test "$relative_target_status" -eq 64
    if grep -F -e typed-sentinel -e anthropic-sentinel \
      -e other-provider-sentinel -e /managed-node-ca \
      -e unrelated-sentinel usage.err >/dev/null; then
      echo "managed MCP launcher exposed an environment value" >&2
      exit 1
    fi
    unset ANTHROPIC_API_KEY GEMINI_API_KEY NODE_EXTRA_CA_CERTS \
      OPENAI_API_KEY UNRELATED_SECRET

    ${pkgs.python3}/bin/python3 ${./overlays/pal-mcp-contract.py} \
      ${pkgs.pal-mcp-server} ${launcher} \
      ${lib.escapeShellArg pkgs.pal-mcp-server.version} -- \
      --inherit ANTHROPIC_API_KEY \
      --inherit DEFAULT_MODEL \
      --inherit DISABLED_TOOLS \
      --inherit GEMINI_API_KEY \
      --inherit HOME \
      --inherit LANG \
      --inherit LC_ALL \
      --inherit LOGNAME \
      --inherit LOG_LEVEL \
      --inherit NIX_SSL_CERT_FILE \
      --inherit NODE_EXTRA_CA_CERTS \
      --inherit OPENAI_API_KEY \
      --inherit PAL_NETWORK_ATTEMPT_MARKER \
      --inherit PAL_NETWORK_GUARD_MARKER \
      --inherit PAL_NETWORK_GUARD_PATH \
      --inherit SHELL \
      --inherit SSL_CERT_FILE \
      --inherit TERM \
      --inherit TMPDIR \
      --inherit USER \
      -- ${networkGuardedPal}

    touch "$out"
  ''
