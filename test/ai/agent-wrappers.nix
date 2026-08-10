{
  pkgs,
  patchAgentPackage,
  claudePackage,
  codexPackage,
  agentHttpHeaderBridge ? null,
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

        if [ "''${CODEX_INTERNAL_WRAPPER_POLICY_PROBE:-}" = v1 ]; then
          if [ -n "''${AGENT_TEST_CODEX_PROBE_READY:-}" ]; then
            : "''${AGENT_TEST_CODEX_PROBE_RELEASE:?}"
            touch "$AGENT_TEST_CODEX_PROBE_READY"
            while [ ! -e "$AGENT_TEST_CODEX_PROBE_RELEASE" ]; do
              sleep 0.01
            done
          fi
          if [ "''${AGENT_TEST_CODEX_PROBE_NO_OUTPUT:-}" = 1 ]; then
            :
          elif [ "''${AGENT_TEST_CODEX_PROBE_NUL:-}" = 1 ]; then
            printf 'man\0age\n'
          elif [ "''${AGENT_TEST_CODEX_PROBE_NO_NEWLINE:-}" = 1 ]; then
            printf %s "''${AGENT_TEST_CODEX_POLICY:-manage}"
          else
            printf '%s\n' "''${AGENT_TEST_CODEX_POLICY:-manage}"
          fi
          exit "''${AGENT_TEST_CODEX_PROBE_EXIT:-0}"
        fi

        : "''${AGENT_TEST_ARGV:?}"
        : "''${AGENT_TEST_ENV:?}"

        : >"$AGENT_TEST_ARGV"
        for argument in "$@"; do
          printf '%s\0' "$argument" >>"$AGENT_TEST_ARGV"
        done
        AGENT_TEST_OPEN_FILE_LIMIT="$(ulimit -Sn)"
        export AGENT_TEST_OPEN_FILE_LIMIT
        env -0 | sort -z >"$AGENT_TEST_ENV"
        exit "''${AGENT_TEST_EXIT:-0}"
      '';
    };

  identityRecorderSource = pkgs.writeText "agent-wrapper-identity-recorder.c" ''
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <unistd.h>

    int main(int argc, char **argv) {
      const char *path = getenv("AGENT_TEST_IDENTITY_FILE");
      const char *exit_value = getenv("AGENT_TEST_EXIT");
      const char *probe = getenv("CODEX_INTERNAL_WRAPPER_POLICY_PROBE");
      const char *probe_policy = getenv("AGENT_TEST_CODEX_POLICY");
      const char *probe_exit = getenv("AGENT_TEST_CODEX_PROBE_EXIT");
      FILE *output;

      (void)argc;
      if (probe != NULL && strcmp(probe, "v1") == 0) {
        if (getenv("AGENT_TEST_CODEX_PROBE_NO_OUTPUT") == NULL) {
          puts(probe_policy == NULL ? "manage" : probe_policy);
        }
        return probe_exit == NULL ? 0 : atoi(probe_exit);
      }
      if (path == NULL || argv[0] == NULL) {
        return 97;
      }
      output = fopen(path, "w");
      if (output == NULL) {
        return 98;
      }
      if (fprintf(output, "%ld\n%s\n", (long)getpid(), argv[0]) < 0 || fclose(output) != 0) {
        return 99;
      }
      return exit_value == NULL ? 0 : atoi(exit_value);
    }
  '';

  identityAgent =
    binary:
    pkgs.stdenv.mkDerivation {
      name = "agent-wrapper-identity-${binary}";
      dontUnpack = true;
      buildPhase = ''
        $CC -Wall -Wextra -Werror ${identityRecorderSource} -o ${binary}
      '';
      installPhase = ''
        install -Dm0755 ${binary} "$out/bin/${binary}"
      '';
    };

  codexProbeTestDouble =
    package:
    package.overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        wrapperPolicyProbeTestDouble = true;
      };
    });

  wrappedClaude = patchAgentPackage testPkgs "claude-code" (fakeAgent "claude");
  realWrappedClaude = patchAgentPackage pkgs "claude-code" claudePackage;
  wrappedCodex = patchAgentPackage testPkgs "codex" (codexProbeTestDouble (fakeAgent "codex"));
  realWrappedCodex = patchAgentPackage testPkgs "codex" codexPackage;
  wrappedNonDarwinCodex = patchAgentPackage nonDarwinTestPkgs "codex" (
    codexProbeTestDouble (fakeAgent "codex")
  );
  identityWrappedClaude = patchAgentPackage testPkgs "claude-code" (identityAgent "claude");
  identityWrappedCodex = patchAgentPackage testPkgs "codex" (
    codexProbeTestDouble (identityAgent "codex")
  );

  networkGuardSource = pkgs.writeText "agent-wrapper-network-guard.c" ''
    #define _GNU_SOURCE
    #include <dlfcn.h>
    #include <errno.h>
    #include <fcntl.h>
    #include <stdio.h>
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
      char event[512];
      const char *program;
      int length;

      #ifdef __APPLE__
      program = getprogname();
      #else
      program = program_invocation_short_name;
      #endif
      if (program == NULL) {
        program = "unknown";
      }
      length = snprintf(event, sizeof(event), "loaded:%ld:%s\n", (long)getpid(), program);
      if (length > 0 && (size_t)length < sizeof(event)) {
        record_event("TASK3_NETWORK_GUARD_LOADED_FILE", event, (size_t)length);
      }
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

  haveBridge = agentHttpHeaderBridge != null && mcpRemote != null;
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
pkgs.runCommand "agent-wrappers-check"
  {
    __darwinAllowLocalNetworking = pkgs.stdenv.isDarwin;
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.openssl
      pkgs.python3
    ];

    CLAUDE_BIN = "${wrappedClaude}/bin/claude";
    CLAUDE_REAL_BIN = "${wrappedClaude}/bin/claude-real";
    CODEX_BIN = "${wrappedCodex}/bin/codex";
    CODEX_NON_DARWIN_BIN = "${wrappedNonDarwinCodex}/bin/codex";
    CLAUDE_IDENTITY_BIN = "${identityWrappedClaude}/bin/claude";
    CLAUDE_REAL_IDENTITY_BIN = "${identityWrappedClaude}/bin/claude-real";
    CODEX_IDENTITY_BIN = "${identityWrappedCodex}/bin/codex";
    REAL_CLAUDE_BIN = "${realWrappedClaude}/bin/claude";
    REAL_CODEX_BIN = "${codexPackage}/bin/codex";
    REAL_PROBED_CODEX_BIN = "${realWrappedCodex.unwrappedPackage}/bin/codex";
    REAL_WRAPPED_CODEX_BIN = "${realWrappedCodex}/bin/codex";
    CODEX_POLICY_RESPONSE_CHECKER =
      realWrappedCodex.unwrappedPackage.passthru.wrapperPolicyResponseChecker;
    CODEX_RAISES_OPEN_FILE_LIMIT = if pkgs.stdenv.isDarwin then "1" else "0";
    NETWORK_GUARD_LIBRARY = "${networkGuard}/lib/libagent-wrapper-network-guard.${networkGuardExtension}";
    NETWORK_GUARD_VARIABLE = if pkgs.stdenv.isDarwin then "DYLD_INSERT_LIBRARIES" else "LD_PRELOAD";

    BRIDGE_BIN = bridgeBin;
    BRIDGE_CLOSURE_PATHS = "${bridgeClosure}/store-paths";
    BRIDGE_NODE_GUARD = ./node-runtime-guard.cjs;
    BRIDGE_ORACLE_PY = ./recording-https-bridge-oracle.py;
    BRIDGE_PRESENT = if haveBridge then "1" else "0";
    PYTHON_BIN = "${pkgs.python3}/bin/python3";
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    mkdir -p "$out"

    ${pkgs.bash}/bin/bash ${./agent-wrappers.sh} claude
    touch "$out/claude-wrapper-contract.ok"
    ${pkgs.bash}/bin/bash ${./agent-wrappers.sh} codex
    touch "$out/codex-wrapper-contract.ok"
    ${pkgs.bash}/bin/bash ${./agent-wrappers.sh} bridge
    ${pkgs.bash}/bin/bash ${./run-bridge-oracle.sh}

    touch "$out/passed"
  ''
