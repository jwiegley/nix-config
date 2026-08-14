{
  darwinConfigurations,
  lib,
  pkgs,
}:

let
  heraHome = darwinConfigurations.hera.config.home-manager.users.johnw;
  piPackage = lib.findFirst (package: lib.getName package == "pi") null heraHome.home.packages;
  expectedCa = heraHome.home.sessionVariables.SSL_CERT_FILE;
  overrideCa = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  probe = pkgs.writeText "pi-node-ca-probe.cjs" ''
    if (process.env.NODE_EXTRA_CA_CERTS !== process.env.PI_TEST_EXPECTED_CA) {
      process.exit(1);
    }
    if (require("node:tls").getCACertificates("extra").length === 0) {
      process.exit(1);
    }
    process.exit(0);
  '';
in
assert piPackage != null;
assert expectedCa != overrideCa;
assert piPackage.pname == "pi";
assert piPackage.version != null;
assert piPackage.passthru.toolRendererWrapperAbi == 1;
pkgs.runCommand "pi-node-ca" { } ''
  ${pkgs.coreutils}/bin/env -u NODE_EXTRA_CA_CERTS -u SSL_CERT_FILE \
    HOME="$TMPDIR" \
    PI_OFFLINE=1 \
    PI_TEST_EXPECTED_CA=${lib.escapeShellArg expectedCa} \
    NODE_OPTIONS=${lib.escapeShellArg "--require=${probe}"} \
    ${piPackage}/bin/pi --version >/dev/null 2>&1

  ${pkgs.coreutils}/bin/env -u SSL_CERT_FILE \
    HOME="$TMPDIR" \
    PI_OFFLINE=1 \
    NODE_EXTRA_CA_CERTS=${lib.escapeShellArg overrideCa} \
    PI_TEST_EXPECTED_CA=${lib.escapeShellArg overrideCa} \
    NODE_OPTIONS=${lib.escapeShellArg "--require=${probe}"} \
    ${piPackage}/bin/pi --version >/dev/null 2>&1

  touch "$out"
''
