{
  curl,
  jq,
  lib,
  tools ? { },
  writeShellApplication,
}:

let
  commands = {
    curl = "${curl}/bin/curl";
    jq = "${jq}/bin/jq";
    security = "/usr/bin/security";
    tailscale = "/Applications/Tailscale.app/Contents/MacOS/Tailscale";
  }
  // tools;
in
writeShellApplication {
  name = "hermes-agent-ops";

  text = ''
    usage() {
      printf '%s\n' \
        'usage: hermes-agent-ops health [--detailed]' \
        '       hermes-agent-ops serve-status' \
        '       hermes-agent-ops serve-apply' >&2
    }

    fail() {
      echo "hermes-agent-ops: $*" >&2
      exit 1
    }

    if [[ $# -lt 1 ]]; then
      usage
      exit 64
    fi

    command=$1
    shift

    case "$command" in
      health)
        if [[ $# -eq 0 ]]; then
          exec ${commands.curl} --disable --noproxy '*' --fail-with-body \
            --silent --show-error http://127.0.0.1:8642/health
        fi
        if [[ $# -ne 1 || $1 != --detailed ]]; then
          usage
          exit 64
        fi

        # Keep the Keychain value out of xtrace, argv, the environment, and
        # curl's config files. curl reads the one request header from stdin.
        set +x
        set +a
        unset api_key
        if ! api_key="$(${commands.security} find-generic-password \
          -s nix-config.hermes.api-server-key -a johnw -w)"; then
          fail "could not read the Hermes API key from the login Keychain"
        fi
        export -n api_key
        if [[ -z "$api_key" || "$api_key" == *$'\n'* || "$api_key" == *$'\r'* ]]; then
          fail "the Hermes API key is empty or contains a line break"
        fi
        printf 'Authorization: Bearer %s\n' "$api_key" \
          | ${commands.curl} --disable --noproxy '*' --fail-with-body \
              --silent --show-error --header @- \
              http://127.0.0.1:8642/health/detailed
        ;;

      serve-status)
        [[ $# -eq 0 ]] || {
          usage
          exit 64
        }
        exec ${commands.tailscale} serve status --json
        ;;

      serve-apply)
        [[ $# -eq 0 ]] || {
          usage
          exit 64
        }
        if ! current="$(${commands.tailscale} serve status --json)"; then
          fail "could not read Tailscale Serve status"
        fi
        if ! state="$(printf '%s\n' "$current" | ${commands.jq} -er '
          if type != "object" then error("expected an object")
          elif length == 0 then "empty"
          elif
            (keys == ["TCP", "Web"]
              or keys == ["AllowFunnel", "TCP", "Web"])
            and .TCP == {"443": {"HTTPS": true}}
            and (.Web | type) == "object"
            and (.Web | length) == 1
            and (.Web | to_entries[0].key | test("^[A-Za-z0-9.-]+:443$"))
            and (.Web | to_entries[0].value)
              == {"Handlers": {"/": {"Proxy": "http://127.0.0.1:8642"}}}
            and (
              (has("AllowFunnel") | not)
              or (
                (.AllowFunnel | type) == "object"
                and (.AllowFunnel | length) == 1
                and (.AllowFunnel | to_entries[0].key)
                  == (.Web | to_entries[0].key)
                and (.AllowFunnel | to_entries[0].value) == false
              )
            )
          then "desired"
          else "unexpected"
          end
        ')"; then
          fail "could not parse Tailscale Serve status"
        fi

        case "$state" in
          desired)
            exit 0
            ;;
          empty)
            exec ${commands.tailscale} serve --bg --yes http://127.0.0.1:8642
            ;;
          *)
            fail "refusing to replace unexpected nonempty Tailscale Serve configuration"
            ;;
        esac
        ;;

      *)
        usage
        exit 64
        ;;
    esac
  '';

  meta = {
    description = "Explicit health and private Tailscale Serve operations for Hermes Agent";
    license = lib.licenses.bsd3;
    mainProgram = "hermes-agent-ops";
    platforms = lib.platforms.darwin;
  };
}
