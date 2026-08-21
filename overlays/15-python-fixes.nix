# Cross-platform Python package compatibility fixes.
_final: prev:

let
  cookieChangesPatch = ./patches/curl-cffi-0.15-cookie-changes.patch;
  tlsErrorCodesPatch = ./patches/curl-cffi-0.15-tls-error-codes.patch;
in
{
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (
      _pfinal: pprev:
      prev.lib.optionalAttrs (pprev ? curl-cffi) {
        curl-cffi = pprev.curl-cffi.overridePythonAttrs (
          old:
          prev.lib.optionalAttrs ((old.version or "") == "0.15.0") (
            {
              passthru = (old.passthru or { }) // {
                nixConfigCurlCffiTransitionOwner = true;
              };
            }
            //
              prev.lib.optionalAttrs (prev ? curl-impersonate && (prev.curl-impersonate.version or "") == "2.1.0")
                {
                  # curl-impersonate 2.1 exposes accepted cookie changes instead
                  # of a final cookie snapshot. Apply the adapted runtime
                  # backport and structured TLS assertions independently. A
                  # strict reverse dry-run makes each patch idempotent if the
                  # same repair reaches this version; partial or divergent
                  # integration fails closed.
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
                      _nix_config_apply_curl_backport ${tlsErrorCodesPatch}
                      unset -f _nix_config_apply_curl_backport
                    '';
                }
          )
        );
      }
    )
  ];
}
