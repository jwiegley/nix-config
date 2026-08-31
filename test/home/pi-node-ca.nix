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
    printf '%s\n' "$@" >>"$PI_TEST_SECURITY_LOG"
    case " $* " in
      *" -s nix-config.test-clio "*) printf '%s' lookup-sentinel ;;
      *" -s nix-config.test-hera "*) exit 44 ;;
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

  ! grep -F '/usr/bin/security find-generic-password' ${piPackage}/bin/pi >/dev/null
  ! grep -F '/usr/bin/security find-generic-password' ${piPackageWithoutSessionCa}/bin/pi >/dev/null
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
