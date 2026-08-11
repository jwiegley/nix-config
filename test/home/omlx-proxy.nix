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
  authMessage = "oMLX proxy exposure requires a protected Basic-auth password file";
  validSettings = {
    enable = true;
    listenAddress = "192.0.2.10";
    allowedSources = [
      "192.0.2.20/32"
      "2001:db8::20/128"
    ];
    authBasicPasswordFile = "/Users/johnw/.config/omlx/proxy.htpasswd";
  };
  defaultScript = pkgs.writeText "omlx-proxy-default-script" (proxyAgentFor { }).script;
  validScript = pkgs.writeText "omlx-proxy-valid-script" (proxyAgentFor validSettings).script;
  omlxScript = (configFor { }).launchd.user.agents.omlx.script;
in
assert builtins.length (proxyAssertionsFor { }) == 3;
assert builtins.all (entry: entry.assertion) (proxyAssertionsFor { });
assert builtins.all (entry: entry.assertion) (proxyAssertionsFor validSettings);
assert !(assertionFor (validSettings // { listenAddress = "0.0.0.0"; }) listenMessage);
assert !(assertionFor (validSettings // { listenAddress = "0"; }) listenMessage);
assert !(assertionFor (validSettings // { listenAddress = "00.00.00.00"; }) listenMessage);
assert !(assertionFor (validSettings // { listenAddress = "999.0.0.1"; }) listenMessage);
assert !(assertionFor (validSettings // { allowedSources = [ ]; }) sourcesMessage);
assert !(assertionFor (validSettings // { allowedSources = [ "all" ]; }) sourcesMessage);
assert !(assertionFor (validSettings // { allowedSources = [ "0.0.0.0/0" ]; }) sourcesMessage);
assert !(assertionFor (validSettings // { allowedSources = [ "0/0" ]; }) sourcesMessage);
assert !(assertionFor (removeAttrs validSettings [ "authBasicPasswordFile" ]) authMessage);
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
  test -f "$default_config"
  test -f "$valid_config"

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
  grep -F 'satisfy all;' "$valid_config"
  grep -F 'allow 192.0.2.20/32;' "$valid_config"
  grep -F 'allow 2001:db8::20/128;' "$valid_config"
  grep -F 'deny all;' "$valid_config"
  grep -F 'auth_basic "oMLX";' "$valid_config"
  grep -F 'auth_basic_user_file /Users/johnw/.config/omlx/proxy.htpasswd;' "$valid_config"
  grep -F 'proxy_pass http://127.0.0.1:8000;' "$valid_config"
  grep -F 'proxy_set_header Authorization "";' "$valid_config"

  grep -F 'auth_file=/Users/johnw/.config/omlx/proxy.htpasswd' ${validScript}
  grep -F '[ -L "$auth_file" ] || [ ! -f "$auth_file" ]' ${validScript}
  grep -F "auth_owner=\$(/usr/bin/stat -f '%u' \"\$auth_file\")" ${validScript}
  grep -F "auth_mode=\$(/usr/bin/stat -f '%Lp' \"\$auth_file\")" ${validScript}
  grep -F '400|600)' ${validScript}

  ${pkgs.gnused}/bin/sed \
    -e "s|^auth_file=.*|auth_file='$TMPDIR/auth'|" \
    -e '/^mkdir -p /,$d' \
    ${validScript} > "$TMPDIR/preflight"
  touch "$TMPDIR/auth"
  chmod 0600 "$TMPDIR/auth"
  ${pkgs.bash}/bin/bash "$TMPDIR/preflight"

  chmod 0644 "$TMPDIR/auth"
  if ${pkgs.bash}/bin/bash "$TMPDIR/preflight" 2>/dev/null; then
    echo "authorization preflight accepted a group/world-readable file" >&2
    exit 1
  fi

  rm "$TMPDIR/auth"
  touch "$TMPDIR/target"
  chmod 0600 "$TMPDIR/target"
  ln -s "$TMPDIR/target" "$TMPDIR/auth"
  if ${pkgs.bash}/bin/bash "$TMPDIR/preflight" 2>/dev/null; then
    echo "authorization preflight accepted a symlink" >&2
    exit 1
  fi

  touch "$out"
''
