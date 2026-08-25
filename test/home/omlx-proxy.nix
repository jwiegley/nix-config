{
  darwinConfigurations,
  pkgs,
}:

let
  inherit (pkgs) lib;
  configuredPkgs = darwinConfigurations.hera.pkgs;
  configForWithTransportPolicy =
    localProviderTransportPolicy: settings:
    (lib.evalModules {
      specialArgs = {
        hostname = "hera";
        inherit localProviderTransportPolicy;
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
  configFor = configForWithTransportPolicy localProviderTransport;
  proxyAgentFor = settings: (configFor settings).launchd.user.agents.llama-swap-https-proxy or null;
  proxyAgentForWithTransportPolicy =
    policy: settings:
    (configForWithTransportPolicy policy settings).launchd.user.agents.llama-swap-https-proxy or null;
  proxyAssertionsFor =
    settings:
    builtins.filter (entry: lib.hasPrefix "oMLX " entry.message) (configFor settings).assertions;
  assertionFor =
    settings: message:
    (lib.findFirst (entry: entry.message == message) (throw "missing oMLX assertion") (
      proxyAssertionsFor settings
    )).assertion;

  listenMessage = "oMLX proxy exposure requires an explicit non-wildcard listen address";
  sourcesMessage = "oMLX proxy exposure requires a non-empty, restricted source allowlist";
  certificateMessage = "oMLX proxy exposure requires explicit absolute certificate and key paths";
  privateKeyMessage = "oMLX proxy exposure requires a host-local private key path";
  gatewayTrustMessage = "oMLX legacy gateway exposure requires an explicit absolute trust path";
  validSettings = {
    enable = true;
    certificateFile = "/Users/test/omlx-test.crt";
    certificateKeyFile = "/Users/test/omlx-test.key";
    legacyGatewayEnable = true;
    trustedCaFile = "/Users/test/omlx-test-ca.crt";
    listenAddress = "192.0.2.10";
    allowedSources = [
      "192.0.2.20/32"
      "2001:db8::20/128"
    ];
  };
  validScript = pkgs.writeText "omlx-proxy-valid-script" (proxyAgentFor validSettings).script;
  restrictedSettings = validSettings // {
    legacyGatewayEnable = false;
    trustedCaFile = "";
  };
  restrictedScript = pkgs.writeText "omlx-proxy-restricted-script" (proxyAgentFor restrictedSettings)
  .script;
  proxyKeyPreflight = import ../../config/omlx-proxy-key-preflight.nix { inherit pkgs; };
  heraSettings = darwinConfigurations.hera.config.johnw.omlxProxy;
  clioSettings = darwinConfigurations.clio.config.johnw.omlxProxy;
  expectedCertificateFiles = {
    clio = ../../config/certs/omlx-clio.crt;
    hera = ../../config/certs/omlx-hera.crt;
  };
  heraScript = pkgs.writeText "omlx-proxy-hera-script" darwinConfigurations.hera.config.launchd.user.agents.llama-swap-https-proxy.script;
  clioScript = pkgs.writeText "omlx-proxy-clio-script" darwinConfigurations.clio.config.launchd.user.agents.llama-swap-https-proxy.script;
  omlxScript = (configFor { }).launchd.user.agents.omlx.script;
  localProviderTransport = import ../../config/ai/local-provider-transport.nix;
  syntheticLocalProviderTransport = {
    client = {
      requestTimeoutMilliseconds = 1111000;
      streamIdleTimeoutMilliseconds = 2222000;
    };
    proxy = {
      upstreamSendTimeoutSeconds = 3333;
      upstreamReadTimeoutSeconds = 4444;
      downstreamSendTimeoutSeconds = 5555;
    };
  };
  syntheticTransportScript = pkgs.writeText "omlx-proxy-synthetic-transport-script" (proxyAgentForWithTransportPolicy syntheticLocalProviderTransport validSettings)
  .script;
  behaviorBackendsTemplate = pkgs.writeText "omlx-proxy-behavior-backends.conf" ''
    server {
      listen unix:@BEHAVIOR_ROOT@/omlx.sock;
      access_log off;
      location / { return 200 "omlx:$http_authorization:$uri"; }
    }
    server {
      listen unix:@BEHAVIOR_ROOT@/legacy.sock;
      access_log off;
      location / { return 200 "legacy:$http_authorization:$uri"; }
    }
  '';
in
assert builtins.length (proxyAssertionsFor { }) == 5;
assert builtins.all (entry: entry.assertion) (proxyAssertionsFor { });
assert builtins.all (entry: entry.assertion) (proxyAssertionsFor validSettings);
assert builtins.all (entry: entry.assertion) (proxyAssertionsFor restrictedSettings);
assert builtins.all (entry: entry.assertion) (proxyAssertionsFor heraSettings);
assert builtins.all (entry: entry.assertion) (proxyAssertionsFor clioSettings);
assert proxyAgentFor { } == null;
assert heraSettings.enable;
assert clioSettings.enable;
assert heraSettings.listenAddress != clioSettings.listenAddress;
assert
  heraSettings.allowedSources == [
    "192.168.1.2/32"
    "192.168.1.5/32"
    "10.6.0.2/32"
  ];
assert clioSettings.allowedSources == [ "192.168.1.4/32" ];
assert builtins.elem "${clioSettings.listenAddress}/32" heraSettings.allowedSources;
assert builtins.elem "${heraSettings.listenAddress}/32" clioSettings.allowedSources;
assert builtins.all
  (
    host:
    let
      settings = darwinConfigurations.${host}.config.johnw.omlxProxy;
    in
    builtins.readFile settings.certificateFile == builtins.readFile expectedCertificateFiles.${host}
    && lib.hasSuffix "omlx-${host}.crt" settings.certificateFile
    && settings.certificateKeyFile == "/Users/johnw/${host}/${host}.lan.key"
    && (
      if host == "hera" then
        settings.legacyGatewayEnable && lib.hasSuffix "/vulcan-root-ca.crt" settings.trustedCaFile
      else
        !settings.legacyGatewayEnable && settings.trustedCaFile == ""
    )
  )
  [
    "clio"
    "hera"
  ];
assert !(assertionFor (validSettings // { listenAddress = "0.0.0.0"; }) listenMessage);
assert !(assertionFor (validSettings // { listenAddress = "0"; }) listenMessage);
assert !(assertionFor (validSettings // { listenAddress = "00.00.00.00"; }) listenMessage);
assert !(assertionFor (validSettings // { listenAddress = "999.0.0.1"; }) listenMessage);
assert !(assertionFor (validSettings // { allowedSources = [ ]; }) sourcesMessage);
assert !(assertionFor (validSettings // { allowedSources = [ "all" ]; }) sourcesMessage);
assert !(assertionFor (validSettings // { allowedSources = [ "0.0.0.0/0" ]; }) sourcesMessage);
assert !(assertionFor (validSettings // { allowedSources = [ "0/0" ]; }) sourcesMessage);
assert !(assertionFor (validSettings // { allowedSources = [ "192.0.2.0/24" ]; }) sourcesMessage);
assert !(assertionFor (validSettings // { allowedSources = [ "2001:db8::/64" ]; }) sourcesMessage);
assert !(assertionFor (validSettings // { allowedSources = [ "2001:db8:1/128" ]; }) sourcesMessage);
assert
  !(assertionFor (validSettings // { allowedSources = [ "2001::db8::1/128" ]; }) sourcesMessage);
assert
  !(assertionFor (validSettings // { allowedSources = [ "2001:db8::zz/128" ]; }) sourcesMessage);
assert !(assertionFor (validSettings // { allowedSources = [ "::::/128" ]; }) sourcesMessage);
assert
  !(assertionFor (validSettings // { certificateKeyFile = "relative.key"; }) certificateMessage);
assert !(assertionFor (validSettings // { certificateFile = "relative.crt"; }) certificateMessage);
assert
  !(assertionFor (
    validSettings // { certificateFile = "/Users/test/invalid\ncertificate.crt"; }
  ) certificateMessage);
assert
  !(assertionFor (
    validSettings // { certificateFile = "/Users/test/invalid certificate.crt"; }
  ) certificateMessage);
assert
  !(assertionFor (
    validSettings // { certificateFile = "/Users/test/invalid;certificate.crt"; }
  ) certificateMessage);
assert
  !(assertionFor (
    validSettings // { certificateKeyFile = "/Users/test/invalid{certificate.key"; }
  ) certificateMessage);
assert
  !(assertionFor (
    validSettings // { certificateKeyFile = "/Users/test/../../tmp/synthetic-private-key"; }
  ) certificateMessage);
assert
  !(assertionFor (
    validSettings // { certificateKeyFile = "/nix/store/synthetic-private-key"; }
  ) privateKeyMessage);
assert
  !(assertionFor (
    validSettings // { certificateKeyFile = "/private/tmp/synthetic-private-key"; }
  ) privateKeyMessage);
assert
  !(assertionFor (
    validSettings // { certificateKeyFile = "/tmp/synthetic-private-key"; }
  ) privateKeyMessage);
assert
  !(assertionFor (
    validSettings // { certificateKeyFile = "/var/tmp/synthetic-private-key"; }
  ) privateKeyMessage);
assert !(assertionFor (validSettings // { trustedCaFile = ""; }) gatewayTrustMessage);
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

  reject_fixed() {
    if grep -Fq -- "$1" "$2"; then
      echo 'generated proxy configuration contains a forbidden directive' >&2
      exit 1
    fi
  }

  valid_config=$(nginx_config ${validScript})
  restricted_config=$(nginx_config ${restrictedScript})
  hera_config=$(nginx_config ${heraScript})
  clio_config=$(nginx_config ${clioScript})
  synthetic_transport_config=$(nginx_config ${syntheticTransportScript})
  test -f "$valid_config"
  test -f "$restricted_config"
  test -f "$hera_config"
  test -f "$clio_config"
  test -f "$synthetic_transport_config"

  grep -F 'listen 192.0.2.10:8443 ssl;' "$valid_config"
  grep -F 'location = /v1' "$valid_config"
  grep -F 'location ^~ /v1/' "$valid_config"
  grep -F 'location ~ ^/v1(?:[^/]|$)' "$valid_config"
  grep -F 'allow 192.0.2.20/32;' "$valid_config"
  grep -F 'allow 2001:db8::20/128;' "$valid_config"
  grep -F 'deny all;' "$valid_config"
  grep -F 'proxy_pass http://127.0.0.1:8000;' "$valid_config"
  grep -F 'proxy_http_version 1.1;' "$valid_config"
  grep -F 'proxy_buffering off;' "$valid_config"
  grep -F 'proxy_set_header Authorization $http_authorization;' "$valid_config"
  test "$(grep -Fc 'proxy_set_header Authorization "";' "$valid_config")" -eq 1
  grep -F 'proxy_send_timeout ${toString localProviderTransport.proxy.upstreamSendTimeoutSeconds};' "$valid_config"
  grep -F 'proxy_read_timeout ${toString localProviderTransport.proxy.upstreamReadTimeoutSeconds};' "$valid_config"
  grep -F 'send_timeout ${toString localProviderTransport.proxy.downstreamSendTimeoutSeconds};' "$valid_config"
  grep -F 'proxy_send_timeout 3333;' "$synthetic_transport_config"
  grep -F 'proxy_read_timeout 4444;' "$synthetic_transport_config"
  grep -F 'send_timeout 5555;' "$synthetic_transport_config"
  reject_fixed 'auth_basic' "$valid_config"

  grep -F 'ssl_certificate /Users/test/omlx-test.crt;' "$valid_config"
  grep -F 'ssl_certificate_key /Users/test/omlx-test.key;' "$valid_config"
  grep -F 'proxy_ssl_trusted_certificate /Users/test/omlx-test-ca.crt;' "$valid_config"
  grep -F 'proxy_ssl_verify on;' "$valid_config"
  grep -F 'proxy_ssl_server_name on;' "$valid_config"
  grep -F 'allow ${validSettings.listenAddress};' "$valid_config"
  test "$(grep -Fc 'return 404;' "$valid_config")" -eq 2
  test "$(grep -Fc 'return 404;' "$restricted_config")" -eq 3
  reject_fixed 'proxy_ssl_trusted_certificate' "$restricted_config"

  grep -F '/bin/omlx-proxy-key-preflight' ${validScript}
  grep -F 'nginx -t -c' ${validScript}
  grep -F -- '-e /Users/johnw/.cache/llama-swap-proxy/error.log' ${validScript}

  for host in hera clio; do
    case "$host" in
      hera)
        config="$hera_config"
        listen=${lib.escapeShellArg heraSettings.listenAddress}
        peer=${lib.escapeShellArg clioSettings.listenAddress}
        ;;
      clio)
        config="$clio_config"
        listen=${lib.escapeShellArg clioSettings.listenAddress}
        peer=${lib.escapeShellArg heraSettings.listenAddress}
        ;;
    esac
    grep -F "listen $listen:8443 ssl;" "$config"
    grep -F "allow $listen;" "$config"
    grep -F "allow $peer/32;" "$config"
    grep -F 'location = /v1' "$config"
    grep -F 'location ^~ /v1/' "$config"
    grep -F 'location ~ ^/v1(?:[^/]|$)' "$config"
    grep -F 'proxy_pass http://127.0.0.1:8000;' "$config"
    grep -F 'proxy_http_version 1.1;' "$config"
    grep -F 'proxy_buffering off;' "$config"
    grep -F 'proxy_set_header Authorization $http_authorization;' "$config"
    grep -F 'proxy_send_timeout ${toString localProviderTransport.proxy.upstreamSendTimeoutSeconds};' "$config"
    grep -F 'proxy_read_timeout ${toString localProviderTransport.proxy.upstreamReadTimeoutSeconds};' "$config"
    grep -F 'send_timeout ${toString localProviderTransport.proxy.downstreamSendTimeoutSeconds};' "$config"
    if [ "$host" = hera ]; then
      grep -F 'proxy_ssl_trusted_certificate' "$config"
      grep -F 'proxy_ssl_verify on;' "$config"
      grep -F 'proxy_ssl_server_name on;' "$config"
      test "$(grep -Fc 'proxy_set_header Authorization "";' "$config")" -eq 1
      test "$(grep -Fc 'return 404;' "$config")" -eq 2
    else
      test "$(grep -Fc 'return 404;' "$config")" -eq 3
      reject_fixed 'proxy_set_header Authorization "";' "$config"
      reject_fixed 'proxy_ssl_trusted_certificate' "$config"
    fi
  done

  nginx_test="$TMPDIR/nginx-test"
  mkdir -p "$nginx_test/client_body"
  ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$nginx_test/server.key" \
    -out "$nginx_test/server.crt" \
    -days 1 -subj '/CN=omlx-test.invalid' >/dev/null 2>&1
  sed \
    -e "s#/Users/test/omlx-test.crt#$nginx_test/server.crt#g" \
    -e "s#/Users/test/omlx-test.key#$nginx_test/server.key#g" \
    -e "s#/Users/test/omlx-test-ca.crt#$nginx_test/server.crt#g" \
    -e "s#/Users/johnw/.cache/llama-swap-proxy#$nginx_test#g" \
    -e 's#proxy_pass https://[^;]*;#proxy_pass http://localhost:8001;#' \
    -e 's#listen [^;]* ssl;#listen localhost:18443 ssl;#' \
    "$valid_config" > "$nginx_test/nginx.conf"
  ${pkgs.nginx}/bin/nginx -t -c "$nginx_test/nginx.conf" \
    -e "$nginx_test/error.log" >/dev/null

  behavior_root="$nginx_test/behavior"
  mkdir -p "$behavior_root/client_body"
  ${pkgs.gnused}/bin/sed \
    -e "s#$nginx_test#$behavior_root#g" \
    -e "s#listen localhost:18443 ssl;#listen unix:$behavior_root/front.sock ssl;#" \
    -e "s#proxy_pass http://[^;]*:8000;#proxy_pass http://unix:$behavior_root/omlx.sock:;#" \
    -e "s#proxy_pass http://localhost:8001;#proxy_pass http://unix:$behavior_root/legacy.sock:;#" \
    -e 's/allow [^;]*;/allow all;/' \
    "$nginx_test/nginx.conf" > "$behavior_root/base.conf"
  cp "$nginx_test/server.crt" "$behavior_root/server.crt"
  cp "$nginx_test/server.key" "$behavior_root/server.key"
  ${pkgs.gnused}/bin/sed \
    -e "s#@BEHAVIOR_ROOT@#$behavior_root#g" \
    ${behaviorBackendsTemplate} > "$behavior_root/backends.conf"
  ${pkgs.gawk}/bin/awk -v include_file="$behavior_root/backends.conf" '
    { lines[NR] = $0 }
    END {
      for (line = 1; line < NR; line++) print lines[line]
      print "  include " include_file ";"
      print lines[NR]
    }
  ' "$behavior_root/base.conf" > "$behavior_root/nginx.conf"
  ${pkgs.nginx}/bin/nginx -t -c "$behavior_root/nginx.conf" \
    -e "$behavior_root/error.log" >/dev/null
  ${pkgs.nginx}/bin/nginx -c "$behavior_root/nginx.conf" \
    -e "$behavior_root/error.log" -g 'daemon off;' &
  behavior_pid=$!
  behavior_term_seconds=5
  behavior_kill_seconds=1
  wait_for_target_or_timer() {
    local target_pid=$1 timer_pid=$2 target_status=0
    while true; do
      if ! jobs -r -p | ${pkgs.gnugrep}/bin/grep -Fxq "$target_pid"; then
        wait "$target_pid" 2>/dev/null || target_status=$?
        kill "$timer_pid" 2>/dev/null || true
        wait "$timer_pid" 2>/dev/null || true
        return "$target_status"
      fi
      if ! jobs -r -p | ${pkgs.gnugrep}/bin/grep -Fxq "$timer_pid"; then
        wait "$timer_pid" 2>/dev/null || true
        return 124
      fi
      ${pkgs.coreutils}/bin/sleep 0.01
    done
  }
  wait_with_deadline() {
    local target_pid=$1 seconds=$2 timer_pid
    ${pkgs.perl}/bin/perl -e \
      'select undef, undef, undef, shift' "$seconds" &
    timer_pid=$!
    wait_for_target_or_timer "$target_pid" "$timer_pid"
  }
  cleanup_behavior() {
    kill "$behavior_pid" 2>/dev/null || true
    status=0
    wait_with_deadline "$behavior_pid" "$behavior_term_seconds" || status=$?
    if [ "$status" -eq 124 ]; then
      kill -KILL "$behavior_pid" 2>/dev/null || true
      wait_with_deadline "$behavior_pid" "$behavior_kill_seconds" || true
    fi
  }
  stop_behavior() {
    if ! kill "$behavior_pid" 2>/dev/null; then
      echo "failed to terminate nginx" >&2
      return 1
    fi
    status=0
    wait_with_deadline "$behavior_pid" "$behavior_term_seconds" || status=$?
    if [ "$status" -eq 124 ]; then
      kill -KILL "$behavior_pid" 2>/dev/null || true
      kill_status=0
      wait_with_deadline "$behavior_pid" "$behavior_kill_seconds" \
        || kill_status=$?
      if [ "$kill_status" -eq 124 ]; then
        echo "nginx remained live after bounded teardown" >&2
        return 1
      fi
      echo "nginx required forced termination" >&2
      return 1
    fi
    case "$status" in
      0 | 143) ;;
      *)
        echo "nginx exited unexpectedly during teardown (status $status)" >&2
        return 1
        ;;
    esac
  }

  (
    race_target_pid=
    cleanup_race_target() {
      if [ -n "$race_target_pid" ]; then
        kill "$race_target_pid" 2>/dev/null || true
        wait "$race_target_pid" 2>/dev/null || true
      fi
    }
    trap cleanup_race_target EXIT
    ${pkgs.perl}/bin/perl -e \
      'select undef, undef, undef, 3' &
    race_target_pid=$!
    ${pkgs.perl}/bin/perl -e 'exit 0' &
    expired_timer_pid=$!
    wait "$expired_timer_pid"
    race_status=0
    wait_for_target_or_timer "$race_target_pid" "$expired_timer_pid" \
      || race_status=$?
    if [ "$race_status" -ne 124 ]; then
      echo 'already-expired teardown timer did not win immediately' >&2
      exit 1
    fi
    if ! kill -0 "$race_target_pid" 2>/dev/null; then
      echo 'deadline regression waited for the finite target' >&2
      exit 1
    fi
  )
  trap 'cleanup_behavior || true' EXIT
  attempts=0
  while [ ! -S "$behavior_root/front.sock" ]; do
    attempts=$((attempts + 1))
    test "$attempts" -lt 100
    ${pkgs.coreutils}/bin/sleep 0.05
  done
  api_body=$(${pkgs.curl}/bin/curl --silent --show-error --insecure \
    --connect-timeout 2 --max-time 5 \
    --unix-socket "$behavior_root/front.sock" \
    -H 'Authorization: Bearer behavioral-sentinel' \
    https://localhost/v1/models)
  if [ "$api_body" != 'omlx:Bearer behavioral-sentinel:/v1/models' ]; then
    echo 'oMLX route did not preserve its bearer and path' >&2
    exit 1
  fi
  legacy_body=$(${pkgs.curl}/bin/curl --silent --show-error --insecure \
    --connect-timeout 2 --max-time 5 \
    --unix-socket "$behavior_root/front.sock" \
    -H 'Authorization: Bearer behavioral-sentinel' \
    https://localhost/chat)
  if [ "$legacy_body" != 'legacy::/chat' ]; then
    echo 'legacy route did not clear authorization' >&2
    exit 1
  fi
  for near_miss in /v1 /v1models; do
    status=$(${pkgs.curl}/bin/curl --silent --show-error --insecure \
      --connect-timeout 2 --max-time 5 \
      --unix-socket "$behavior_root/front.sock" \
      -H 'Authorization: Bearer behavioral-sentinel' \
      --output /dev/null --write-out '%{http_code}' \
      "https://localhost$near_miss")
    if [ "$status" != 404 ]; then
      printf 'near-miss API route did not fail closed: %s returned %s\n' \
        "$near_miss" "$status" >&2
      exit 1
    fi
  done
  stop_behavior
  trap - EXIT

  stubborn_ready="$behavior_root/stubborn-ready"
  stubborn_pid_file="$behavior_root/stubborn-pid"
  ${pkgs.perl}/bin/perl -e '
    $SIG{TERM} = "IGNORE";
    my ($ready_path, $pid_path) = @ARGV;
    open my $pid_file, ">", $pid_path or die "create PID marker: $!";
    print {$pid_file} "$$\n" or die "write PID marker: $!";
    close $pid_file or die "close PID marker: $!";
    open my $ready, ">", $ready_path or die "create readiness marker: $!";
    close $ready or die "close readiness marker: $!";
    while (1) { select undef, undef, undef, 60; }
  ' "$stubborn_ready" "$stubborn_pid_file" &
  behavior_pid=$!
  behavior_term_seconds=0
  behavior_kill_seconds=1
  trap 'cleanup_behavior || true' EXIT
  attempts=0
  while [ ! -e "$stubborn_ready" ] || [ ! -e "$stubborn_pid_file" ]; do
    attempts=$((attempts + 1))
    test "$attempts" -lt 100
    ${pkgs.coreutils}/bin/sleep 0.05
  done
  if [ "$(${pkgs.coreutils}/bin/cat "$stubborn_pid_file")" != "$behavior_pid" ]; then
    echo 'strict teardown fixture PID did not match its managed job' >&2
    exit 1
  fi
  strict_status=0
  stop_behavior 2>"$behavior_root/stubborn-stop.err" || strict_status=$?
  if [ "$strict_status" -eq 0 ]; then
    echo 'strict teardown accepted forced termination' >&2
    exit 1
  fi
  if [ "$(${pkgs.coreutils}/bin/cat "$behavior_root/stubborn-stop.err")" \
    != 'nginx required forced termination' ]; then
    echo 'strict teardown did not report exact forced termination' >&2
    exit 1
  fi
  if kill -0 "$behavior_pid" 2>/dev/null \
    || jobs -p | ${pkgs.gnugrep}/bin/grep -Fxq "$behavior_pid"; then
    echo 'strict teardown left its forced-termination fixture live' >&2
    exit 1
  fi
  trap - EXIT

  sed \
    -e "s#/Users/test/omlx-test.crt#$nginx_test/server.crt#g" \
    -e "s#/Users/test/omlx-test.key#$nginx_test/server.key#g" \
    -e "s#/Users/johnw/.cache/llama-swap-proxy#$nginx_test/restricted#g" \
    -e 's#proxy_pass http://127.0.0.1:8000;#proxy_pass http://localhost:8001;#' \
    -e 's#listen [^;]* ssl;#listen localhost:18444 ssl;#' \
    "$restricted_config" > "$nginx_test/restricted.conf"
  mkdir -p "$nginx_test/restricted/client_body"
  ${pkgs.nginx}/bin/nginx -t -c "$nginx_test/restricted.conf" \
    -e "$nginx_test/restricted/error.log" >/dev/null

  preflight_root="$TMPDIR/key-preflight"
  mkdir -p "$preflight_root"
  ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$preflight_root/matching.key" \
    -out "$preflight_root/matching.crt" \
    -days 1 -subj '/CN=omlx-preflight.invalid' >/dev/null 2>&1
  ${pkgs.openssl}/bin/openssl genpkey -algorithm RSA \
    -pkeyopt rsa_keygen_bits:2048 \
    -out "$preflight_root/mismatched.key" >/dev/null 2>&1
  chmod 600 "$preflight_root/matching.key" "$preflight_root/mismatched.key"
  preflight_owner="$(/usr/bin/stat -f '%Su' "$preflight_root/matching.key")"

  ${proxyKeyPreflight}/bin/omlx-proxy-key-preflight \
    "$preflight_root/matching.crt" "$preflight_root/matching.key" "$preflight_owner"
  if ${proxyKeyPreflight}/bin/omlx-proxy-key-preflight \
    "$preflight_root/matching.crt" "$preflight_root/mismatched.key" "$preflight_owner" \
    >"$preflight_root/mismatch.out" 2>"$preflight_root/mismatch.err"; then
    exit 1
  fi
  grep -F 'certificate and private key do not match' "$preflight_root/mismatch.err"

  chmod 644 "$preflight_root/matching.key"
  if ${proxyKeyPreflight}/bin/omlx-proxy-key-preflight \
    "$preflight_root/matching.crt" "$preflight_root/matching.key" "$preflight_owner" \
    >"$preflight_root/mode.out" 2>"$preflight_root/mode.err"; then
    exit 1
  fi
  grep -F 'private key ownership or mode is unsafe' "$preflight_root/mode.err"
  chmod 600 "$preflight_root/matching.key"

  ln -s "$preflight_root/matching.key" "$preflight_root/symlink.key"
  if ${proxyKeyPreflight}/bin/omlx-proxy-key-preflight \
    "$preflight_root/matching.crt" "$preflight_root/symlink.key" "$preflight_owner" \
    >"$preflight_root/symlink.out" 2>"$preflight_root/symlink.err"; then
    exit 1
  fi
  grep -F 'private key is not a regular host file' "$preflight_root/symlink.err"

  if ${proxyKeyPreflight}/bin/omlx-proxy-key-preflight \
    "$preflight_root/matching.crt" "$preflight_root/matching.key" synthetic-owner \
    >"$preflight_root/owner.out" 2>"$preflight_root/owner.err"; then
    exit 1
  fi
  grep -F 'private key ownership or mode is unsafe' "$preflight_root/owner.err"

  touch "$out"
''
