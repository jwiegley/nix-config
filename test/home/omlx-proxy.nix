{
  darwinConfigurations,
  pkgs,
}:

let
  inherit (pkgs) lib;
  configuredPkgs = darwinConfigurations.hera.pkgs;
  configFor =
    settings:
    (lib.evalModules {
      specialArgs = {
        hostname = "hera";
        pkgs = configuredPkgs;
      };
      modules = [
        {
          options = {
            assertions = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    assertion = lib.mkOption { type = lib.types.bool; };
                    message = lib.mkOption { type = lib.types.str; };
                  };
                }
              );
              default = [ ];
            };
            launchd = lib.mkOption {
              type = lib.types.raw;
              default = { };
            };
          };
        }
        ../../config/launchd.nix
        { johnw.omlxProxy = settings; }
      ];
    }).config;
  proxyAgentFor = settings: (configFor settings).launchd.user.agents.llama-swap-https-proxy;
  proxyAssertionsFor =
    settings:
    builtins.filter (entry: lib.hasPrefix "oMLX proxy exposure" entry.message)
      (configFor settings).assertions;
  assertionFor =
    settings: message:
    (lib.findFirst (entry: entry.message == message) (throw "missing oMLX assertion") (
      proxyAssertionsFor settings
    )).assertion;

  listenMessage = "oMLX proxy exposure requires an explicit non-wildcard listen address";
  sourcesMessage = "oMLX proxy exposure requires a non-empty, restricted source allowlist";
  validSettings = {
    enable = true;
    listenAddress = "192.0.2.10";
    allowedSources = [
      "192.0.2.20/32"
      "2001:db8::20/128"
    ];
  };
  defaultScript = pkgs.writeText "omlx-proxy-default-script" (proxyAgentFor { }).script;
  validScript = pkgs.writeText "omlx-proxy-valid-script" (proxyAgentFor validSettings).script;
  heraSettings = darwinConfigurations.hera.config.johnw.omlxProxy;
  clioSettings = darwinConfigurations.clio.config.johnw.omlxProxy;
  heraScript = pkgs.writeText "omlx-proxy-hera-script" darwinConfigurations.hera.config.launchd.user.agents.llama-swap-https-proxy.script;
  clioScript = pkgs.writeText "omlx-proxy-clio-script" darwinConfigurations.clio.config.launchd.user.agents.llama-swap-https-proxy.script;
  omlxScript = (configFor { }).launchd.user.agents.omlx.script;
in
assert builtins.length (proxyAssertionsFor { }) == 2;
assert builtins.all (entry: entry.assertion) (proxyAssertionsFor { });
assert builtins.all (entry: entry.assertion) (proxyAssertionsFor validSettings);
assert
  heraSettings == {
    enable = true;
    listenAddress = "192.168.1.4";
    allowedSources = [
      "192.168.1.2/32"
      "192.168.1.5/32"
      "10.6.0.2/32"
    ];
  };
assert
  clioSettings == {
    enable = false;
    listenAddress = "127.0.0.1";
    allowedSources = [ ];
  };
assert !(assertionFor (validSettings // { listenAddress = "0.0.0.0"; }) listenMessage);
assert !(assertionFor (validSettings // { listenAddress = "0"; }) listenMessage);
assert !(assertionFor (validSettings // { listenAddress = "00.00.00.00"; }) listenMessage);
assert !(assertionFor (validSettings // { listenAddress = "999.0.0.1"; }) listenMessage);
assert !(assertionFor (validSettings // { allowedSources = [ ]; }) sourcesMessage);
assert !(assertionFor (validSettings // { allowedSources = [ "all" ]; }) sourcesMessage);
assert !(assertionFor (validSettings // { allowedSources = [ "0.0.0.0/0" ]; }) sourcesMessage);
assert !(assertionFor (validSettings // { allowedSources = [ "0/0" ]; }) sourcesMessage);
assert lib.hasInfix "--host 127.0.0.1 --port 8000" omlxScript;
pkgs.runCommand "omlx-proxy-client-boundary" { } ''
  set -eu

  nginx_config() {
    ${pkgs.gawk}/bin/awk '
      {
        for (field = 1; field <= NF; field++) {
          if ($field == "-c") {
            print $(field + 1)
            exit
          }
        }
      }
    ' "$1"
  }

  default_config=$(nginx_config ${defaultScript})
  valid_config=$(nginx_config ${validScript})
  hera_config=$(nginx_config ${heraScript})
  clio_config=$(nginx_config ${clioScript})
  test -f "$default_config"
  test -f "$valid_config"
  test -f "$hera_config"
  test -f "$clio_config"

  grep -F 'listen 8443 ssl;' "$default_config"
  if grep -F 'location /v1/' "$default_config"; then
    echo "default gateway unexpectedly exposes oMLX" >&2
    exit 1
  fi
  if grep -F 'proxy_pass http://127.0.0.1:8000;' "$default_config"; then
    echo "default gateway unexpectedly reaches oMLX" >&2
    exit 1
  fi

  grep -F 'listen 192.0.2.10:8443 ssl;' "$valid_config"
  grep -F 'location /v1/' "$valid_config"
  grep -F 'allow 192.0.2.20/32;' "$valid_config"
  grep -F 'allow 2001:db8::20/128;' "$valid_config"
  grep -F 'deny all;' "$valid_config"
  grep -F 'proxy_pass http://127.0.0.1:8000;' "$valid_config"
  grep -F 'proxy_set_header Authorization $http_authorization;' "$valid_config"
  ! grep -F 'proxy_set_header Authorization "";' "$valid_config"
  ! grep -F 'auth_basic' "$valid_config"

  grep -F 'listen 192.168.1.4:8443 ssl;' "$hera_config"
  grep -F 'allow 192.168.1.2/32;' "$hera_config"
  grep -F 'allow 192.168.1.5/32;' "$hera_config"
  grep -F 'allow 10.6.0.2/32;' "$hera_config"
  grep -F 'proxy_pass http://127.0.0.1:8000;' "$hera_config"
  grep -F 'proxy_set_header Authorization $http_authorization;' "$hera_config"
  ! grep -F 'proxy_set_header Authorization "";' "$hera_config"

  grep -F 'listen 8443 ssl;' "$clio_config"
  ! grep -F 'location /v1/' "$clio_config"
  ! grep -F 'proxy_pass http://127.0.0.1:8000;' "$clio_config"

  touch "$out"
''
