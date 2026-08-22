# Cross-platform Python package compatibility fixes.
final: prev:

let
  cookieChangesPatch = ./patches/curl-cffi-0.15-cookie-changes.patch;
  testPortPatch = ./patches/curl-cffi-0.15-test-port.patch;
  tlsErrorCodesPatch = ./patches/curl-cffi-0.15-tls-error-codes.patch;
  websocketPartialSendPatch = ./patches/curl-cffi-0.15-websocket-partial-send.patch;
in
{
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (
      _pfinal: pprev:
      prev.lib.optionalAttrs (pprev ? curl-cffi) {
        curl-cffi = pprev.curl-cffi.overridePythonAttrs (
          old:
          let
            curlRpath = "${final.lib.getLib final.curl-impersonate}/lib";
            rpathFlags = "-rpath ${curlRpath}";
            appendRpath =
              value:
              let
                inherited = if value == null then "" else builtins.toString value;
                tokens = prev.lib.filter (token: token != "") (prev.lib.splitString " " inherited);
                hasRpath =
                  remaining:
                  builtins.length remaining >= 2
                  && (
                    (builtins.head remaining == "-rpath" && builtins.head (builtins.tail remaining) == curlRpath)
                    || hasRpath (builtins.tail remaining)
                  );
                normalized = prev.lib.concatStringsSep " " tokens;
              in
              if hasRpath tokens then
                normalized
              else
                prev.lib.optionalString (normalized != "") (normalized + " ") + rpathFlags;
            oldEnv = if (old.env or null) == null then { } else old.env;
            linkerFlagsInEnv = oldEnv ? NIX_LDFLAGS;
            darwinLinkerFlags =
              assert prev.lib.assertMsg (
                !(old ? NIX_LDFLAGS && linkerFlagsInEnv)
              ) "curl-cffi defines NIX_LDFLAGS both directly and in env";
              if linkerFlagsInEnv then
                {
                  env = oldEnv // {
                    NIX_LDFLAGS = appendRpath oldEnv.NIX_LDFLAGS;
                  };
                }
              else
                {
                  NIX_LDFLAGS = appendRpath (old.NIX_LDFLAGS or null);
                };
          in
          prev.lib.optionalAttrs ((old.version or "") == "0.15.0") (
            {
              passthru = (old.passthru or { }) // {
                nixConfigCurlCffiTransitionOwner = true;
              };
            }
            //
              prev.lib.optionalAttrs
                (final ? curl-impersonate && (final.curl-impersonate.version or "") == "2.1.0")
                (
                  {
                    # curl-impersonate 2.1 exposes accepted cookie changes instead
                    # of a final cookie snapshot. Apply the adapted runtime
                    # backport, collision-free local test fixture, and structured
                    # TLS assertions independently. A strict reverse dry-run makes
                    # each patch idempotent if the same repair reaches this version;
                    # partial or divergent integration fails closed.
                    postPatch =
                      prev.lib.optionalString (old ? postPatch && old.postPatch != null) (old.postPatch + "\n")
                      + ''
                        _nix_config_apply_curl_backport() {
                          local backport="$1"
                          if patch --dry-run --batch --forward --fuzz=0 -p1 < "$backport" >/dev/null 2>&1; then
                            patch --batch --forward --fuzz=0 -p1 < "$backport"
                          elif patch --dry-run --batch --reverse --fuzz=0 -p1 < "$backport" >/dev/null 2>&1; then
                            echo "curl-cffi backport is already integrated"
                          else
                            echo "curl-cffi backport neither applies nor reverses cleanly" >&2
                            return 1
                          fi
                        }

                        _nix_config_apply_curl_backport ${cookieChangesPatch}
                        _nix_config_apply_curl_backport ${testPortPatch}
                        _nix_config_apply_curl_backport ${tlsErrorCodesPatch}
                        _nix_config_apply_curl_backport ${websocketPartialSendPatch}
                        unset -f _nix_config_apply_curl_backport
                      '';
                  }
                  # The system-library patch links the extension against an
                  # @rpath dylib but does not supply a Darwin runtime search
                  # path. Keep the dependency loadable through the package's
                  # own runtime output.
                  // prev.lib.optionalAttrs final.stdenv.hostPlatform.isDarwin darwinLinkerFlags
                )
          )
        );
      }
    )
  ];
}
