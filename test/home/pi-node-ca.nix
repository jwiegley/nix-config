{
  darwinConfigurations,
  lib,
  pkgs,
}:

let
  heraHome = darwinConfigurations.hera.config.home-manager.users.johnw;
  piPackage = lib.findFirst (package: lib.getName package == "pi") null heraHome.home.packages;
  heraWithoutSessionCa =
    (darwinConfigurations.hera.extendModules {
      modules = [
        ({ lib, ... }: {
          home-manager.users.johnw.home.sessionVariables = lib.mkForce { };
        })
      ];
    }).config.home-manager.users.johnw;
  piPackageWithoutSessionCa = lib.findFirst (
    package: lib.getName package == "pi"
  ) null heraWithoutSessionCa.home.packages;
  logicalHeraHome =
    (darwinConfigurations.hera.extendModules {
      modules = [
        (
          {
            inputs,
            lib,
            ...
          }:
          {
            home-manager.extraSpecialArgs = lib.mkForce {
              hostname = "synthetic-workstation";
              inherit inputs;
              nixManagedAiHomeClass = "hera";
            };
          }
        )
      ];
    }).config.home-manager.users.johnw;
  logicalHeraCodexPackage = lib.findFirst (
    package: lib.getName package == "codex"
  ) null logicalHeraHome.home.packages;
  expectedCa = heraHome.home.sessionVariables.SSL_CERT_FILE;
  standardCa = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  overrideCa = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  wrapRuntimeEnvironment = import ../../flake/ai/wrappers/runtime-environment.nix {
    inherit lib pkgs;
  };
  fakeKeychain = pkgs.writeShellScript "fake-keychain-security" ''
    set -eu
    test "$#" -eq 6
    test "$1" = find-generic-password
    test "$2" = -s
    test "$4" = -a
    test "$5" = johnw
    test "$6" = -w
    printf '%s\n' "$@" >>"$PI_TEST_SECURITY_LOG"
    case "$3" in
      nix-config.test-clio) printf '%s' lookup-sentinel ;;
      nix-config.test-hera) exit 44 ;;
      *) exit 64 ;;
    esac
  '';
  requiredFakeKeychain = pkgs.writeShellScript "fake-required-keychain-security" ''
    set -eu
    test -z "''${_nix_managed_credential+x}"
    test "$#" -eq 6
    test "$1" = find-generic-password
    test "$2" = -s
    test "$4" = -a
    test "$5" = johnw
    test "$6" = -w
    printf '%s\n' "$@" >>"$RUNTIME_TEST_SECURITY_LOG"
    if [ "''${RUNTIME_TEST_MISSING_SERVICE-}" = "$3" ]; then
      exit 44
    fi
    case "$3" in
      nix-config.test-openai) printf '%s' openai-secret-sentinel ;;
      nix-config.test-api-server) printf '%s' api-server-secret-sentinel ;;
      nix-config.test-qdrant) printf '%s' qdrant-secret-sentinel ;;
      nix-config.test-postgres) printf '%s' postgres-secret-sentinel ;;
      *) exit 64 ;;
    esac
  '';
  environmentProbe =
    (pkgs.writeShellScriptBin "runtime-environment-probe" ''
      set -eu
      test "''${OMLX_CLIO_API_KEY-}" = "$PI_TEST_EXPECT_CLIO"
      if [ "''${PI_TEST_EXPECT_HERA_SET-0}" = 1 ]; then
        test "''${OMLX_HERA_API_KEY-}" = "$PI_TEST_EXPECT_HERA"
      else
        test -z "''${OMLX_HERA_API_KEY+x}"
      fi
      test "''${TEST_DEFAULT-}" = "$PI_TEST_EXPECT_DEFAULT"
    '')
    // {
      meta = { };
      passthru = { };
      pname = "runtime-environment-probe";
      version = "1";
    };
  wrappedEnvironmentProbe = wrapRuntimeEnvironment {
    defaults.TEST_DEFAULT = "managed-default";
    keychainCommand = "${fakeKeychain}";
    keychainCredentials = {
      OMLX_CLIO_API_KEY = {
        account = "johnw";
        service = "nix-config.test-clio";
      };
      OMLX_HERA_API_KEY = {
        account = "johnw";
        service = "nix-config.test-hera";
      };
    };
    package = environmentProbe;
    program = "runtime-environment-probe";
  };
  fallbackEnvironmentProbe = wrapRuntimeEnvironment {
    defaults = {
      OMLX_CLIO_API_KEY = "clio-fallback";
      OMLX_HERA_API_KEY = "hera-fallback";
      TEST_DEFAULT = "managed-default";
    };
    package = environmentProbe;
    program = "runtime-environment-probe";
  };
  nestedEnvironmentProbe = wrapRuntimeEnvironment {
    keychainCommand = "${fakeKeychain}";
    keychainCredentials = {
      OMLX_CLIO_API_KEY = {
        account = "johnw";
        service = "nix-config.test-clio";
      };
      OMLX_HERA_API_KEY = {
        account = "johnw";
        service = "nix-config.test-hera";
      };
    };
    package = fallbackEnvironmentProbe;
    program = "runtime-environment-probe";
  };
  requiredProbeScript = pkgs.writeShellScript "required-runtime-environment-probe" ''
    set -eu
    if [ -n "''${RUNTIME_TEST_INVOKED-}" ]; then
      : >"$RUNTIME_TEST_INVOKED"
    fi
    case "''${RUNTIME_TEST_MODE-credentials}" in
      credentials)
        test "$OPENAI_API_KEY" = "$RUNTIME_TEST_EXPECT_OPENAI"
        test "$API_SERVER_KEY" = "$RUNTIME_TEST_EXPECT_API_SERVER"
        test "$QDRANT_API_KEY" = "$RUNTIME_TEST_EXPECT_QDRANT"
        test "$PGPASSWORD" = "$RUNTIME_TEST_EXPECT_POSTGRES"
        test "$#" -eq 3
        test "$1" = first
        test "$2" = "two words"
        test -z "$3"
        ;;
      exit)
        exit "$RUNTIME_TEST_EXIT"
        ;;
      signal)
        trap 'exit 42' TERM
        : >"$RUNTIME_TEST_READY"
        for _ in $(${pkgs.coreutils}/bin/seq 1 100); do
          ${pkgs.coreutils}/bin/sleep 0.1
        done
        exit 97
        ;;
      *) exit 64 ;;
    esac
  '';
  requiredProbePackage = pkgs.runCommand "required-runtime-environment-probe" { } ''
    mkdir -p "$out/bin"
    for program in hermes hermes-agent hermes-acp; do
      ln -s ${requiredProbeScript} "$out/bin/$program"
    done
  '';
  requiredCredentialMetadata = {
    OPENAI_API_KEY = {
      account = "johnw";
      service = "nix-config.test-openai";
    };
    API_SERVER_KEY = {
      account = "johnw";
      service = "nix-config.test-api-server";
    };
    QDRANT_API_KEY = {
      account = "johnw";
      service = "nix-config.test-qdrant";
    };
    PGPASSWORD = {
      account = "johnw";
      service = "nix-config.test-postgres";
    };
  };
  requiredEnvironmentProbe = wrapRuntimeEnvironment {
    keychainCommand = "${requiredFakeKeychain}";
    keychainCredentials = requiredCredentialMetadata;
    package = requiredProbePackage;
    programs = [
      "hermes"
      "hermes-agent"
      "hermes-acp"
    ];
    requiredKeychainCredentials = builtins.attrNames requiredCredentialMetadata;
  };
  overlappingEnvironmentEvaluation =
    builtins.tryEval
      (wrapRuntimeEnvironment {
        defaults.OMLX_CLIO_API_KEY = "invalid-default";
        keychainCommand = "${fakeKeychain}";
        keychainCredentials.OMLX_CLIO_API_KEY = {
          account = "johnw";
          service = "nix-config.test-clio";
        };
        package = environmentProbe;
        program = "runtime-environment-probe";
      }).outPath;
  invalidProgramEvaluation =
    builtins.tryEval
      (wrapRuntimeEnvironment {
        package = environmentProbe;
        program = "runtime environment probe";
      }).outPath;
  invalidRequiredCredentialEvaluation =
    builtins.tryEval
      (wrapRuntimeEnvironment {
        keychainCommand = "${requiredFakeKeychain}";
        keychainCredentials = requiredCredentialMetadata;
        package = requiredProbePackage;
        programs = [ "hermes" ];
        requiredKeychainCredentials = [ "NOT_CONFIGURED" ];
      }).outPath;
  mixedProgramsEvaluation =
    builtins.tryEval
      (wrapRuntimeEnvironment {
        package = requiredProbePackage;
        program = "hermes";
        programs = [ "hermes" ];
      }).outPath;
  probe = pkgs.writeText "pi-node-ca-probe.cjs" ''
    if (process.env.NODE_EXTRA_CA_CERTS !== process.env.PI_TEST_EXPECTED_CA) {
      process.exit(1);
    }
    if (require("node:tls").getCACertificates("extra").length === 0) {
      process.exit(1);
    }
    if (process.env.OMLX_CLIO_API_KEY !== process.env.PI_TEST_EXPECT_CLIO) {
      process.exit(1);
    }
    if (process.env.OMLX_HERA_API_KEY !== process.env.PI_TEST_EXPECT_HERA) {
      process.exit(1);
    }
    process.exit(0);
  '';
in
assert piPackage != null;
assert piPackageWithoutSessionCa != null;
assert logicalHeraCodexPackage != null;
assert expectedCa != overrideCa;
assert piPackage.pname == "pi";
assert piPackage.version != null;
assert piPackage.passthru.toolRendererWrapperAbi == 1;
assert !overlappingEnvironmentEvaluation.success;
assert !invalidProgramEvaluation.success;
assert !invalidRequiredCredentialEvaluation.success;
assert !mixedProgramsEvaluation.success;
pkgs.runCommand "pi-node-ca" { } ''
  lookup_log="$TMPDIR/keychain-lookup.log"
  ${pkgs.coreutils}/bin/env -u OMLX_CLIO_API_KEY -u OMLX_HERA_API_KEY \
    PI_TEST_SECURITY_LOG="$lookup_log" \
    PI_TEST_EXPECT_CLIO=lookup-sentinel \
    PI_TEST_EXPECT_DEFAULT=managed-default \
    ${wrappedEnvironmentProbe}/bin/runtime-environment-probe \
    >"$TMPDIR/lookup.out" 2>"$TMPDIR/lookup.err"
  test ! -s "$TMPDIR/lookup.out"
  test ! -s "$TMPDIR/lookup.err"
  grep -F 'nix-config.test-clio' "$lookup_log" >/dev/null
  grep -F 'nix-config.test-hera' "$lookup_log" >/dev/null
  ! grep -F 'lookup-sentinel' "$lookup_log"

  xtrace_log="$TMPDIR/keychain-xtrace.log"
  ${pkgs.coreutils}/bin/env -u OMLX_CLIO_API_KEY -u OMLX_HERA_API_KEY \
    PI_TEST_SECURITY_LOG="$xtrace_log" \
    PI_TEST_EXPECT_CLIO=lookup-sentinel \
    PI_TEST_EXPECT_DEFAULT=managed-default \
    ${pkgs.bash}/bin/bash -x \
    ${wrappedEnvironmentProbe}/bin/runtime-environment-probe \
    >"$TMPDIR/xtrace.out" 2>"$TMPDIR/xtrace.err"
  test ! -s "$TMPDIR/xtrace.out"
  ! grep -F 'lookup-sentinel' "$TMPDIR/xtrace.err"
  ! grep -F 'lookup-sentinel' "$xtrace_log"

  override_log="$TMPDIR/keychain-override.log"
  OMLX_CLIO_API_KEY=explicit-clio \
    OMLX_HERA_API_KEY=explicit-hera \
    TEST_DEFAULT=explicit-default \
    PI_TEST_SECURITY_LOG="$override_log" \
    PI_TEST_EXPECT_CLIO=explicit-clio \
    PI_TEST_EXPECT_HERA=explicit-hera \
    PI_TEST_EXPECT_HERA_SET=1 \
    PI_TEST_EXPECT_DEFAULT=explicit-default \
    ${wrappedEnvironmentProbe}/bin/runtime-environment-probe
  test ! -e "$override_log"

  nested_log="$TMPDIR/keychain-over-fallback.log"
  ${pkgs.coreutils}/bin/env -u OMLX_CLIO_API_KEY -u OMLX_HERA_API_KEY \
    PI_TEST_SECURITY_LOG="$nested_log" \
    PI_TEST_EXPECT_CLIO=lookup-sentinel \
    PI_TEST_EXPECT_HERA=hera-fallback \
    PI_TEST_EXPECT_HERA_SET=1 \
    PI_TEST_EXPECT_DEFAULT=managed-default \
    ${nestedEnvironmentProbe}/bin/runtime-environment-probe
  grep -F 'nix-config.test-clio' "$nested_log" >/dev/null
  grep -F 'nix-config.test-hera' "$nested_log" >/dev/null
  ! grep -F 'lookup-sentinel' "$nested_log"

  openai_secret=openai-secret-sentinel
  api_server_secret=api-server-secret-sentinel
  qdrant_secret=qdrant-secret-sentinel
  postgres_secret=postgres-secret-sentinel
  for program in hermes hermes-agent hermes-acp; do
    required_log="$TMPDIR/$program-required-keychain.log"
    (
      unset OPENAI_API_KEY API_SERVER_KEY QDRANT_API_KEY PGPASSWORD
      export RUNTIME_TEST_SECURITY_LOG="$required_log"
      export RUNTIME_TEST_EXPECT_OPENAI="$openai_secret"
      export RUNTIME_TEST_EXPECT_API_SERVER="$api_server_secret"
      export RUNTIME_TEST_EXPECT_QDRANT="$qdrant_secret"
      export RUNTIME_TEST_EXPECT_POSTGRES="$postgres_secret"
      ${requiredEnvironmentProbe}/bin/$program first 'two words' ""
    )
    test "$(grep -c '^find-generic-password$' "$required_log")" -eq 4
    for secret in "$openai_secret" "$api_server_secret" "$qdrant_secret" "$postgres_secret"; do
      ! grep -F "$secret" "$required_log"
      ! grep -F "$secret" ${requiredEnvironmentProbe}/bin/$program
    done
  done

  missing_log="$TMPDIR/required-keychain-missing.log"
  missing_invoked="$TMPDIR/required-keychain-missing.invoked"
  set +e
  (
    export OPENAI_API_KEY=untrusted-openai
    export API_SERVER_KEY=untrusted-api-server
    export QDRANT_API_KEY=untrusted-qdrant
    export PGPASSWORD=untrusted-postgres
    export RUNTIME_TEST_SECURITY_LOG="$missing_log"
    export RUNTIME_TEST_MISSING_SERVICE=nix-config.test-qdrant
    export RUNTIME_TEST_INVOKED="$missing_invoked"
    ${requiredEnvironmentProbe}/bin/hermes first 'two words' ""
  ) >"$TMPDIR/required-keychain-missing.out" 2>"$TMPDIR/required-keychain-missing.err"
  missing_status=$?
  set -e
  test "$missing_status" -eq 78
  test ! -e "$missing_invoked"
  test ! -s "$TMPDIR/required-keychain-missing.out"
  grep -Fx 'required runtime credential QDRANT_API_KEY is unavailable' \
    "$TMPDIR/required-keychain-missing.err" >/dev/null
  for secret in "$openai_secret" "$api_server_secret" "$qdrant_secret" "$postgres_secret"; do
    ! grep -F "$secret" "$TMPDIR/required-keychain-missing.err"
    ! grep -F "$secret" "$missing_log"
  done

  preseeded_log="$TMPDIR/required-keychain-preseeded.log"
  (
    export OPENAI_API_KEY=untrusted-openai
    export API_SERVER_KEY=untrusted-api-server
    export QDRANT_API_KEY=untrusted-qdrant
    export PGPASSWORD=untrusted-postgres
    export RUNTIME_TEST_SECURITY_LOG="$preseeded_log"
    export RUNTIME_TEST_EXPECT_OPENAI="$openai_secret"
    export RUNTIME_TEST_EXPECT_API_SERVER="$api_server_secret"
    export RUNTIME_TEST_EXPECT_QDRANT="$qdrant_secret"
    export RUNTIME_TEST_EXPECT_POSTGRES="$postgres_secret"
    ${requiredEnvironmentProbe}/bin/hermes first 'two words' ""
  )
  test "$(grep -c '^find-generic-password$' "$preseeded_log")" -eq 4
  for untrusted in untrusted-openai untrusted-api-server untrusted-qdrant untrusted-postgres; do
    ! grep -F "$untrusted" "$preseeded_log"
    ! grep -F "$untrusted" ${requiredEnvironmentProbe}/bin/hermes
  done

  required_xtrace_log="$TMPDIR/required-keychain-xtrace.log"
  (
    unset OPENAI_API_KEY API_SERVER_KEY QDRANT_API_KEY PGPASSWORD
    export RUNTIME_TEST_SECURITY_LOG="$required_xtrace_log"
    export RUNTIME_TEST_EXPECT_OPENAI="$openai_secret"
    export RUNTIME_TEST_EXPECT_API_SERVER="$api_server_secret"
    export RUNTIME_TEST_EXPECT_QDRANT="$qdrant_secret"
    export RUNTIME_TEST_EXPECT_POSTGRES="$postgres_secret"
    ${pkgs.bash}/bin/bash -ax ${requiredEnvironmentProbe}/bin/hermes first 'two words' ""
  ) >"$TMPDIR/required-keychain-xtrace.out" 2>"$TMPDIR/required-keychain-xtrace.err"
  test ! -s "$TMPDIR/required-keychain-xtrace.out"
  for secret in "$openai_secret" "$api_server_secret" "$qdrant_secret" "$postgres_secret"; do
    ! grep -F "$secret" "$TMPDIR/required-keychain-xtrace.err"
    ! grep -F "$secret" "$required_xtrace_log"
  done

  for program in hermes hermes-agent hermes-acp; do
    exit_log="$TMPDIR/$program-exit-keychain.log"
    set +e
    (
      export RUNTIME_TEST_SECURITY_LOG="$exit_log"
      export RUNTIME_TEST_MODE=exit
      export RUNTIME_TEST_EXIT=37
      ${requiredEnvironmentProbe}/bin/$program
    )
    exit_status=$?
    set -e
    test "$exit_status" -eq 37
    test "$(grep -c '^find-generic-password$' "$exit_log")" -eq 4
  done

  signal_ready="$TMPDIR/required-keychain-signal.ready"
  signal_log="$TMPDIR/required-keychain-signal.log"
  (
    export RUNTIME_TEST_SECURITY_LOG="$signal_log"
    export RUNTIME_TEST_MODE=signal
    export RUNTIME_TEST_READY="$signal_ready"
    exec ${requiredEnvironmentProbe}/bin/hermes
  ) &
  signal_pid=$!
  for _ in $(${pkgs.coreutils}/bin/seq 1 50); do
    test ! -e "$signal_ready" || break
    ${pkgs.coreutils}/bin/sleep 0.1
  done
  test -e "$signal_ready"
  kill -TERM "$signal_pid"
  set +e
  wait "$signal_pid"
  signal_status=$?
  set -e
  test "$signal_status" -eq 42
  test "$(grep -c '^find-generic-password$' "$signal_log")" -eq 4

  for host in clio hera; do
    certificate=${../../config/certs}/omlx-$host.crt
    ${pkgs.openssl}/bin/openssl verify \
      -CAfile ${../../config/certs/vulcan-root-ca.crt} \
      -untrusted "$certificate" \
      -purpose sslserver \
      -verify_hostname "$host.lan" \
      "$certificate" >/dev/null
    ${pkgs.openssl}/bin/openssl verify \
      -CAfile ${lib.escapeShellArg expectedCa} \
      -untrusted "$certificate" \
      -purpose sslserver \
      -verify_hostname "$host.lan" \
      "$certificate" >/dev/null
    ${pkgs.openssl}/bin/openssl x509 -in "$certificate" \
      -noout -ext basicConstraints | grep -F 'CA:FALSE' >/dev/null
    if ${pkgs.openssl}/bin/openssl x509 -in "$certificate" \
      -noout -ext keyUsage | grep -F 'Certificate Sign' >/dev/null; then
      exit 1
    fi
  done

  expected_bundle="$TMPDIR/expected-ca-bundle.crt"
  ${pkgs.coreutils}/bin/cat \
    ${lib.escapeShellArg standardCa} \
    ${../../config/certs/vulcan-root-ca.crt} \
    >"$expected_bundle"
  ${pkgs.diffutils}/bin/cmp "$expected_bundle" ${lib.escapeShellArg expectedCa}

  grep -F '/usr/bin/security find-generic-password' ${piPackage}/bin/pi >/dev/null
  ${pkgs.python3}/bin/python3 - ${piPackage}/bin/pi <<'PY'
  import pathlib
  import sys

  script = pathlib.Path(sys.argv[1]).read_text()
  expected = {
      "OMLX_CLIO_API_KEY": "nix-config.omlx-clio-client",
      "OMLX_HERA_API_KEY": "nix-config.omlx-hera-client",
  }
  markers = {name: "''${" + name + "+x}" for name in expected}
  positions = {name: script.index(marker) for name, marker in markers.items()}
  cleanup = script.index("unset _nix_managed_credential", max(positions.values()))
  for name, service in expected.items():
      following = [position for other, position in positions.items() if other != name and position > positions[name]]
      end = min(following + [cleanup])
      block = script[positions[name]:end]
      if service not in block:
          raise SystemExit(f"{name} is not paired with its production Keychain service")
      for other_service in set(expected.values()) - {service}:
          if other_service in block:
              raise SystemExit(f"{name} is paired with the wrong production Keychain service")
  PY
  grep -F '/usr/bin/security find-generic-password' \
    ${piPackageWithoutSessionCa}/bin/pi >/dev/null
  grep -F 'nix-config.omlx-hera-client' \
    ${logicalHeraCodexPackage}/bin/codex >/dev/null

  ${pkgs.coreutils}/bin/env -u NODE_EXTRA_CA_CERTS -u SSL_CERT_FILE \
    HOME="$TMPDIR" \
    OMLX_CLIO_API_KEY=clio-wrapper-sentinel \
    OMLX_HERA_API_KEY=hera-wrapper-sentinel \
    PI_TEST_EXPECT_CLIO=clio-wrapper-sentinel \
    PI_TEST_EXPECT_HERA=hera-wrapper-sentinel \
    PI_OFFLINE=1 \
    PI_TEST_EXPECTED_CA=${lib.escapeShellArg expectedCa} \
    NODE_OPTIONS=${lib.escapeShellArg "--require=${probe}"} \
    ${piPackage}/bin/pi --version >/dev/null 2>&1

  ${pkgs.coreutils}/bin/env -u SSL_CERT_FILE \
    HOME="$TMPDIR" \
    OMLX_CLIO_API_KEY=clio-wrapper-sentinel \
    OMLX_HERA_API_KEY=hera-wrapper-sentinel \
    PI_TEST_EXPECT_CLIO=clio-wrapper-sentinel \
    PI_TEST_EXPECT_HERA=hera-wrapper-sentinel \
    PI_OFFLINE=1 \
    NODE_EXTRA_CA_CERTS=${lib.escapeShellArg overrideCa} \
    PI_TEST_EXPECTED_CA=${lib.escapeShellArg overrideCa} \
    NODE_OPTIONS=${lib.escapeShellArg "--require=${probe}"} \
    ${piPackage}/bin/pi --version >/dev/null 2>&1

  ${pkgs.coreutils}/bin/env -u NODE_EXTRA_CA_CERTS -u SSL_CERT_FILE \
    -u OMLX_CLIO_API_KEY -u OMLX_HERA_API_KEY \
    HOME="$TMPDIR" \
    PI_OFFLINE=1 \
    PI_TEST_EXPECT_CLIO=dummy-key \
    PI_TEST_EXPECT_HERA=dummy-key \
    PI_TEST_EXPECTED_CA=${lib.escapeShellArg expectedCa} \
    NODE_OPTIONS=${lib.escapeShellArg "--require=${probe}"} \
    ${piPackage}/bin/pi --version >/dev/null 2>&1

  touch "$out"
''
