{
  pkgs,
  patchAgentPackage,
  claudePackage,
  codexPackage,
  agentHttpHeaderBridge ? null,
  agentHttpHeaderBridgeOutput ? null,
  mcpRemote ? null,
}:

let
  fakeId = pkgs.writeShellScriptBin "id" ''
    set -euo pipefail
    if [ "$#" -eq 1 ] && [ "$1" = -u ]; then
      printf '%s\n' "''${AGENT_TEST_UID:?}"
    else
      exec ${pkgs.coreutils}/bin/id "$@"
    fi
  '';

  fakeStat = pkgs.writeShellScriptBin "stat" ''
    set -euo pipefail
    if [ "$#" -eq 3 ] && [ "$1" = -c ] && [ "$2" = %u ]; then
      printf '%s\n' "''${AGENT_TEST_UID:?}"
    else
      exec ${pkgs.coreutils}/bin/stat "$@"
    fi
  '';

  testCoreutils = pkgs.symlinkJoin {
    name = "agent-wrapper-test-coreutils";
    paths = [ pkgs.coreutils ];
    postBuild = ''
      rm -- "$out/bin/id" "$out/bin/stat"
      ln -s ${fakeId}/bin/id "$out/bin/id"
      ln -s ${fakeStat}/bin/stat "$out/bin/stat"
    '';
  };

  testPkgs = pkgs // {
    coreutils = testCoreutils;
  };

  nonDarwinTestPkgs = testPkgs // {
    stdenv = testPkgs.stdenv // {
      isDarwin = false;
    };
  };

  fakeAgent =
    binary:
    pkgs.writeShellApplication {
      name = binary;
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        set -euo pipefail
        : "''${AGENT_TEST_ARGV:?}"
        : "''${AGENT_TEST_ENV:?}"

        : >"$AGENT_TEST_ARGV"
        for argument in "$@"; do
          printf '%s\0' "$argument" >>"$AGENT_TEST_ARGV"
        done
        env -0 | sort -z >"$AGENT_TEST_ENV"
        exit "''${AGENT_TEST_EXIT:-0}"
      '';
    };

  wrappedClaude = patchAgentPackage testPkgs "claude-code" (fakeAgent "claude");
  realWrappedClaude = patchAgentPackage pkgs "claude-code" claudePackage;
  wrappedCodex = patchAgentPackage testPkgs "codex" (
    (fakeAgent "codex") // { inherit (codexPackage) version; }
  );
  wrappedNonDarwinCodex = patchAgentPackage nonDarwinTestPkgs "codex" (
    (fakeAgent "codex") // { inherit (codexPackage) version; }
  );
  wrappedDroid = patchAgentPackage testPkgs "droid" (fakeAgent "droid");

  networkGuardSource = pkgs.writeText "agent-wrapper-network-guard.c" ''
    #define _GNU_SOURCE
    #include <dlfcn.h>
    #include <errno.h>
    #include <fcntl.h>
    #include <stdlib.h>
    #include <sys/socket.h>
    #include <unistd.h>

    static int (*real_socket)(int, int, int);

    static void record_event(const char *environment, const char *event, size_t length) {
      const char *path = getenv(environment);
      if (path != NULL) {
        int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) {
          (void)write(fd, event, length);
          (void)close(fd);
        }
      }
    }

    __attribute__((constructor)) static void record_loaded(void) {
      record_event("TASK3_NETWORK_GUARD_LOADED_FILE", "loaded\n", 7);
    }

    static int guarded_socket(int domain, int type, int protocol) {
      if (domain == AF_INET || domain == AF_INET6) {
        record_event("TASK3_NETWORK_ATTEMPT_FILE", "network\n", 8);
        errno = EPERM;
        return -1;
      }

      if (real_socket == NULL) {
        real_socket = dlsym(RTLD_NEXT, "socket");
      }
      if (real_socket == NULL) {
        errno = ENOSYS;
        return -1;
      }
      return real_socket(domain, type, protocol);
    }

    #ifdef __APPLE__
    __attribute__((used)) static struct {
      const void *replacement;
      const void *replacee;
    } socket_interpose __attribute__((section("__DATA,__interpose"))) = {
      (const void *)guarded_socket,
      (const void *)socket,
    };
    #else
    int socket(int domain, int type, int protocol) {
      return guarded_socket(domain, type, protocol);
    }
    #endif
  '';

  networkGuardExtension = if pkgs.stdenv.isDarwin then "dylib" else "so";
  networkGuard = pkgs.stdenv.mkDerivation {
    name = "agent-wrapper-network-guard";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.stdenv.cc ];
    buildPhase = ''
      runHook preBuild
      $CC -Wall ${
        if pkgs.stdenv.isDarwin then "-dynamiclib" else "-shared -fPIC -ldl"
      } ${networkGuardSource} -o libagent-wrapper-network-guard.${networkGuardExtension}
      runHook postBuild
    '';
    installPhase = ''
      install -Dm0444 libagent-wrapper-network-guard.${networkGuardExtension} \
        "$out/lib/libagent-wrapper-network-guard.${networkGuardExtension}"
    '';
  };

  missingBridge = pkgs.writeShellScript "missing-agent-http-header-bridge" ''
    printf '%s\n' 'agent-http-header-bridge: package is absent' >&2
    exit 127
  '';

  haveBridge =
    agentHttpHeaderBridge != null
    && agentHttpHeaderBridgeOutput != null
    && agentHttpHeaderBridge == agentHttpHeaderBridgeOutput
    && mcpRemote != null;
  bridgeBin =
    if agentHttpHeaderBridge == null then
      missingBridge
    else
      "${agentHttpHeaderBridge}/bin/agent-http-header-bridge";
  bridgeClosure =
    if agentHttpHeaderBridge == null then
      pkgs.writeTextDir "store-paths" ""
    else
      pkgs.closureInfo { rootPaths = [ agentHttpHeaderBridge ]; };
in
assert (codexPackage.version or null) == "0.144.6";
pkgs.runCommand "agent-wrappers-check"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.openssl
      pkgs.python3
    ];

    CLAUDE_BIN = "${wrappedClaude}/bin/claude";
    CLAUDE_REAL_BIN = "${wrappedClaude}/bin/claude-real";
    CODEX_BIN = "${wrappedCodex}/bin/codex";
    CODEX_NON_DARWIN_BIN = "${wrappedNonDarwinCodex}/bin/codex";
    DROID_BIN = "${wrappedDroid}/bin/droid";
    REAL_CLAUDE_BIN = "${realWrappedClaude}/bin/claude";
    REAL_CODEX_BIN = "${codexPackage}/bin/codex";
    CODEX_APP_IS_COMMAND = if pkgs.stdenv.isDarwin then "1" else "0";
    NETWORK_GUARD_LIBRARY = "${networkGuard}/lib/libagent-wrapper-network-guard.${networkGuardExtension}";
    NETWORK_GUARD_VARIABLE = if pkgs.stdenv.isDarwin then "DYLD_INSERT_LIBRARIES" else "LD_PRELOAD";

    BRIDGE_BIN = bridgeBin;
    BRIDGE_CLOSURE_PATHS = "${bridgeClosure}/store-paths";
    BRIDGE_NODE_GUARD = ./node-runtime-guard.cjs;
    BRIDGE_ORACLE_PY = ./recording-https-bridge-oracle.py;
    BRIDGE_PRESENT = if haveBridge then "1" else "0";
    MCP_REMOTE_REV = if mcpRemote == null then "" else mcpRemote.rev or "";
    MCP_REMOTE_NAR_HASH = if mcpRemote == null then "" else mcpRemote.narHash or "";
    MCP_REMOTE_LOCK_HASH =
      if mcpRemote == null || !builtins.pathExists "${mcpRemote}/pnpm-lock.yaml" then
        ""
      else
        builtins.hashFile "sha256" "${mcpRemote}/pnpm-lock.yaml";
    PYTHON_BIN = "${pkgs.python3}/bin/python3";
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    ${pkgs.bash}/bin/bash ${./agent-wrappers.sh}
    ${pkgs.bash}/bin/bash ${./run-bridge-oracle.sh}

    mkdir -p "$out"
    touch "$out/passed"
  ''
