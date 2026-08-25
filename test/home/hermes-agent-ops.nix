{ pkgs }:

let
  fakeSecurity = pkgs.writeShellScript "hermes-agent-ops-fake-security" ''
    set -euo pipefail
    {
      printf 'argc=%s' "$#"
      printf ' %q' "$@"
      printf '\n'
    } >>"$HERMES_OPS_TEST_LOG/security.argv"
    case "''${HERMES_OPS_SECURITY_MODE:-present}" in
      missing) exit 44 ;;
      empty) exit 0 ;;
      line-feed) printf 'hermes-test-key\ninjected' ;;
      carriage-return) printf 'hermes-test-key\rinjected' ;;
      present) printf %s 'hermes-test-key-0123456789' ;;
      *) exit 45 ;;
    esac
  '';
  fakeCurl = pkgs.writeShellScript "hermes-agent-ops-fake-curl" ''
    set -euo pipefail
    {
      printf 'argc=%s' "$#"
      printf ' %q' "$@"
      printf '\n'
    } >>"$HERMES_OPS_TEST_LOG/curl.argv"
    [[ -z "''${api_key+x}" ]] || exit 48
    if ${pkgs.coreutils}/bin/env \
      | ${pkgs.gnugrep}/bin/grep -F hermes-test-key-0123456789 >/dev/null; then
      exit 47
    fi
    ${pkgs.coreutils}/bin/cat >"$HERMES_OPS_TEST_LOG/curl.stdin"
    printf '%s\n' '{"status":"ok"}'
  '';
  fakeTailscale = pkgs.writeShellScript "hermes-agent-ops-fake-tailscale" ''
    set -euo pipefail
    {
      printf 'argc=%s' "$#"
      printf ' %q' "$@"
      printf '\n'
    } >>"$HERMES_OPS_TEST_LOG/tailscale.argv"
    if [[ $# -eq 3 && $1 == serve && $2 == status && $3 == --json ]]; then
      [[ "''${HERMES_OPS_TAILSCALE_MODE:-ok}" != status-failure ]] || exit 49
      printf '%s\n' "''${HERMES_OPS_SERVE_JSON:?}"
    elif [[ $# -eq 4 && $1 == serve && $2 == --bg && $3 == --yes \
      && $4 == http://127.0.0.1:8642 ]]; then
      exit 0
    else
      exit 46
    fi
  '';
  ops = pkgs.callPackage ../../packages/hermes-agent-ops.nix {
    tools = {
      curl = fakeCurl;
      security = fakeSecurity;
      tailscale = fakeTailscale;
    };
  };
in
pkgs.runCommand "hermes-agent-ops-contract" { } ''
  fail() {
    echo "hermes-agent-ops test: $1" >&2
    exit 1
  }
  new_case() {
    export HERMES_OPS_TEST_LOG="$work/$1"
    export HERMES_OPS_SECURITY_MODE=present
    export HERMES_OPS_TAILSCALE_MODE=ok
    ${pkgs.coreutils}/bin/mkdir -p "$HERMES_OPS_TEST_LOG"
  }
  expect_failure() {
    label=$1
    shift
    status=0
    "$@" >"$HERMES_OPS_TEST_LOG/$label.stdout" \
      2>"$HERMES_OPS_TEST_LOG/$label.stderr" || status=$?
    [[ $status -ne 0 ]] || fail "$label unexpectedly succeeded"
  }
  one_call() {
    [[ "$(${pkgs.coreutils}/bin/wc -l <"$1")" -eq 1 ]] \
      || fail "$2 made an unexpected number of calls"
    [[ "$(${pkgs.coreutils}/bin/cat "$1")" == "$3" ]] \
      || fail "$2 used unexpected arguments"
  }

  work="$TMPDIR/hermes-agent-ops"
  secret=hermes-test-key-0123456789
  public_curl='argc=7 --disable --noproxy \* --fail-with-body --silent --show-error http://127.0.0.1:8642/health'
  detailed_curl='argc=9 --disable --noproxy \* --fail-with-body --silent --show-error --header @- http://127.0.0.1:8642/health/detailed'
  security_args='argc=6 find-generic-password -s nix-config.hermes.api-server-key -a johnw -w'
  desired='{"TCP":{"443":{"HTTPS":true}},"Web":{"hera.example.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:8642"}}}}}'
  ${pkgs.coreutils}/bin/mkdir -p "$work"
  ! ${pkgs.gnugrep}/bin/grep -F "$secret" ${ops}/bin/hermes-agent-ops >/dev/null \
    || fail "the runtime Keychain value entered the helper store path"

  new_case public-health
  ${ops}/bin/hermes-agent-ops health >"$HERMES_OPS_TEST_LOG/stdout"
  one_call "$HERMES_OPS_TEST_LOG/curl.argv" public-health "$public_curl"
  [[ ! -s "$HERMES_OPS_TEST_LOG/curl.stdin" ]] \
    || fail "public-health sent unexpected request input"
  [[ ! -e "$HERMES_OPS_TEST_LOG/security.argv" ]] \
    || fail "public-health read the Keychain"

  new_case detailed-health
  api_key=preexisting-export HERMES_OPS_SECURITY_MODE=present \
    ${pkgs.bash}/bin/bash -ax ${ops}/bin/hermes-agent-ops health --detailed \
      >"$HERMES_OPS_TEST_LOG/stdout" 2>"$HERMES_OPS_TEST_LOG/stderr"
  one_call "$HERMES_OPS_TEST_LOG/security.argv" detailed-health-security "$security_args"
  one_call "$HERMES_OPS_TEST_LOG/curl.argv" detailed-health-curl "$detailed_curl"
  [[ "$(${pkgs.coreutils}/bin/cat "$HERMES_OPS_TEST_LOG/curl.stdin")" \
    == "Authorization: Bearer $secret" ]] \
    || fail "detailed-health did not send the reviewed Bearer header on stdin"
  for path in \
    "$HERMES_OPS_TEST_LOG/security.argv" \
    "$HERMES_OPS_TEST_LOG/curl.argv" \
    "$HERMES_OPS_TEST_LOG/stdout" \
    "$HERMES_OPS_TEST_LOG/stderr"; do
    ! ${pkgs.gnugrep}/bin/grep -F "$secret" "$path" >/dev/null \
      || fail "detailed-health exposed the key outside curl stdin"
  done

  for mode in missing empty line-feed carriage-return; do
    new_case "detailed-$mode"
    export HERMES_OPS_SECURITY_MODE=$mode
    expect_failure "$mode" ${ops}/bin/hermes-agent-ops health --detailed
    [[ ! -e "$HERMES_OPS_TEST_LOG/curl.argv" ]] \
      || fail "detailed-$mode invoked curl"
  done

  new_case serve-status
  HERMES_OPS_SERVE_JSON='{}' \
    ${ops}/bin/hermes-agent-ops serve-status >"$HERMES_OPS_TEST_LOG/stdout"
  one_call "$HERMES_OPS_TEST_LOG/tailscale.argv" serve-status \
    'argc=3 serve status --json'

  new_case serve-apply-empty
  HERMES_OPS_SERVE_JSON='{}' ${ops}/bin/hermes-agent-ops serve-apply
  [[ "$(${pkgs.gnused}/bin/sed -n '1p' "$HERMES_OPS_TEST_LOG/tailscale.argv")" \
    == 'argc=3 serve status --json' ]] \
    || fail "serve-apply-empty did not inspect status first"
  [[ "$(${pkgs.gnused}/bin/sed -n '2p' "$HERMES_OPS_TEST_LOG/tailscale.argv")" \
    == 'argc=4 serve --bg --yes http://127.0.0.1:8642' ]] \
    || fail "serve-apply-empty used the wrong apply command"
  [[ "$(${pkgs.coreutils}/bin/wc -l <"$HERMES_OPS_TEST_LOG/tailscale.argv")" -eq 2 ]] \
    || fail "serve-apply-empty made an unexpected Tailscale call"

  new_case serve-apply-desired
  HERMES_OPS_SERVE_JSON="$desired" ${ops}/bin/hermes-agent-ops serve-apply
  one_call "$HERMES_OPS_TEST_LOG/tailscale.argv" serve-apply-desired \
    'argc=3 serve status --json'

  new_case serve-apply-funnel-disabled
  funnel_disabled="$(${pkgs.jq}/bin/jq -c \
    '. + {AllowFunnel: {"hera.example.ts.net:443": false}}' <<<"$desired")"
  HERMES_OPS_SERVE_JSON="$funnel_disabled" \
    ${ops}/bin/hermes-agent-ops serve-apply
  one_call "$HERMES_OPS_TEST_LOG/tailscale.argv" serve-apply-funnel-disabled \
    'argc=3 serve status --json'

  new_case serve-apply-unexpected
  unexpected="$(${pkgs.jq}/bin/jq -c \
    '. + {AllowFunnel: {"hera.example.ts.net:443": true}}' <<<"$desired")"
  export HERMES_OPS_SERVE_JSON="$unexpected"
  expect_failure unexpected ${ops}/bin/hermes-agent-ops serve-apply
  one_call "$HERMES_OPS_TEST_LOG/tailscale.argv" serve-apply-unexpected \
    'argc=3 serve status --json'

  new_case serve-apply-status-failure
  export HERMES_OPS_SERVE_JSON='{}'
  export HERMES_OPS_TAILSCALE_MODE=status-failure
  expect_failure status-failure ${ops}/bin/hermes-agent-ops serve-apply
  one_call "$HERMES_OPS_TEST_LOG/tailscale.argv" serve-apply-status-failure \
    'argc=3 serve status --json'

  new_case serve-apply-malformed
  export HERMES_OPS_SERVE_JSON='{not-json'
  expect_failure malformed ${ops}/bin/hermes-agent-ops serve-apply
  one_call "$HERMES_OPS_TEST_LOG/tailscale.argv" serve-apply-malformed \
    'argc=3 serve status --json'

  ! ${pkgs.gnugrep}/bin/grep -RFi funnel "$work"/*/tailscale.argv >/dev/null \
    || fail "an operator path invoked Tailscale Funnel"

  ${pkgs.coreutils}/bin/touch "$out"
''
