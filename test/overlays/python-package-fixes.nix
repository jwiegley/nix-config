{
  configured,
  lib,
  runCommand,
}:

let
  overlay = import ../../overlays/15-python-fixes.nix;

  fakeCurlCffi =
    {
      version,
      postPatch ? "",
    }:
    {
      inherit postPatch version;
      patches = [ "existing.patch" ];
      overridePythonAttrs =
        transform:
        let
          old = {
            inherit postPatch version;
            patches = [ "existing.patch" ];
            passthru = { };
          };
        in
        old // transform old;
    };

  evaluate =
    {
      curlCffiVersion,
      curlImpersonateVersion,
      oldPostPatch ? "",
    }:
    let
      prev = {
        inherit lib;
        curl-impersonate.version = curlImpersonateVersion;
        pythonPackagesExtensions = [ ];
      };
      extension = builtins.head (overlay null prev).pythonPackagesExtensions;
    in
    extension null {
      curl-cffi = fakeCurlCffi {
        version = curlCffiVersion;
        postPatch = oldPostPatch;
      };
    };

  transitional = evaluate {
    curlCffiVersion = "0.15.0";
    curlImpersonateVersion = "2.1.0";
  };
  earlierImpersonate = evaluate {
    curlCffiVersion = "0.15.0";
    curlImpersonateVersion = "1.5.6";
  };
  futureCurlCffi = evaluate {
    curlCffiVersion = "0.16.0";
    curlImpersonateVersion = "2.1.0";
  };
  inheritedPostPatch = evaluate {
    curlCffiVersion = "0.15.0";
    curlImpersonateVersion = "2.1.0";
    oldPostPatch = "printf '%s' inherited-post-patch > \"$TMPDIR/inherited-post-patch\"";
  };

  configuredCurlCffi = configured.python3Packages.curl-cffi;
  configuredTransition = (configured.curl-impersonate.version or "") == "2.1.0";
  configuredPostPatch = configuredCurlCffi.postPatch or "";
  configuredPython = configured.python3.withPackages (pythonPackages: [ pythonPackages.curl-cffi ]);
in
assert transitional.curl-cffi.patches == [ "existing.patch" ];
assert transitional.curl-cffi.passthru.nixConfigCurlCffiTransitionOwner;
assert lib.hasInfix "curl-cffi-0.15-cookie-changes.patch" transitional.curl-cffi.postPatch;
assert lib.hasInfix "curl-cffi-0.15-tls-error-codes.patch" transitional.curl-cffi.postPatch;
assert earlierImpersonate.curl-cffi.patches == [ "existing.patch" ];
assert earlierImpersonate.curl-cffi.passthru.nixConfigCurlCffiTransitionOwner;
assert earlierImpersonate.curl-cffi.postPatch == "";
assert !(lib.hasInfix "curl-cffi-0.15-cookie-changes.patch" earlierImpersonate.curl-cffi.postPatch);
assert
  !(lib.hasInfix "curl-cffi-0.15-tls-error-codes.patch" earlierImpersonate.curl-cffi.postPatch);
assert futureCurlCffi.curl-cffi.patches == [ "existing.patch" ];
assert futureCurlCffi.curl-cffi.postPatch == "";
assert lib.hasInfix "\"$TMPDIR/inherited-post-patch\"\n_nix_config_apply_curl_backport"
  inheritedPostPatch.curl-cffi.postPatch;
assert
  configuredCurlCffi.version == "0.15.0"
  || throw "remove the retired curl-cffi 0.15 transition overlay and check";
assert configuredCurlCffi.passthru.nixConfigCurlCffiTransitionOwner or false;
assert
  !configuredTransition
  || (
    lib.hasInfix "curl-cffi-0.15-cookie-changes.patch" configuredPostPatch
    && lib.hasInfix "curl-cffi-0.15-tls-error-codes.patch" configuredPostPatch
  );
runCommand "python-package-fixes-tests"
  (
    {
      nativeBuildInputs = [ configuredPython ];
    }
    // lib.optionalAttrs configuredTransition {
      __darwinAllowLocalNetworking = true;
    }
  )
  ''
    source_root="$TMPDIR/curl-cffi-source"
    cp -R ${configuredCurlCffi.src} "$source_root"
    chmod -R u+w "$source_root"
    installed_wrapper="$(python -c 'import curl_cffi._wrapper; print(curl_cffi._wrapper.__file__)')"
    cp "$installed_wrapper" "$source_root/curl_cffi/"
    cd "$source_root"

    transition_hook="$TMPDIR/apply-curl-cffi-transition"
    inherited_hook="$TMPDIR/apply-curl-cffi-transition-after-inherited-hook"
    cat > "$transition_hook" <<'HOOK'
    ${transitional.curl-cffi.postPatch}
    HOOK
    cat > "$inherited_hook" <<'HOOK'
    ${inheritedPostPatch.curl-cffi.postPatch}
    HOOK

    # Exercise the transition hook mechanics against the locked 0.15 source:
    # pristine preimage first, then exact postimage without a duplicate patch.
    # This is source-level evidence only while the configured native dependency
    # remains pre-2.1; the installed-session check below activates only for the
    # exact production transition tuple.
    bash -e "$inherited_hook"
    test "$(cat "$TMPDIR/inherited-post-patch")" = inherited-post-patch
    bash -e "$transition_hook"

    PYTHONPATH="$source_root" python - <<'PY'
    from curl_cffi.const import CurlInfo
    from curl_cffi.requests.cookies import Cookies

    assert CurlInfo.COOKIECHANGES == 0x400000 + 1000

    for stored_domain in ("example.invalid", ".example.invalid"):
        cookies = Cookies()
        cookies.set("target", "remove", domain=stored_domain, path="/nested")
        cookies.set("target", "keep", domain=stored_domain, path="/other")
        cookies.set("sibling", "keep", domain=stored_domain, path="/nested")
        cookies.update_cookies_from_curl_changes(
            [b"DELETE\t.example.invalid\tTRUE\t/nested\tFALSE\t0\ttarget\t"]
        )
        remaining = {(cookie.name, cookie.path) for cookie in cookies.jar}
        assert ("target", "/nested") not in remaining
        assert ("target", "/other") in remaining
        assert ("sibling", "/nested") in remaining

    sentinel = b"cookie-value-canary"
    malformed = (
        b"BROKEN\t.example.invalid\tTRUE\t/nested\tFALSE\t0\ttarget\t" + sentinel
    )
    try:
        Cookies().update_cookies_from_curl_changes([malformed])
    except ValueError as error:
        assert str(error) == "Invalid curl cookie change record"
        assert sentinel.decode() not in str(error)
    else:
        raise AssertionError("malformed cookie change was accepted")

    PY

    # A source containing an altered applied hunk is neither the pristine
    # preimage nor the exact postimage. Both independent patches must reject
    # that state instead of hiding a partial or divergent integration.
    cookie_divergent="$TMPDIR/cookie-divergent"
    cp -R "$source_root" "$cookie_divergent"
    chmod -R u+w "$cookie_divergent"
    python - "$cookie_divergent/curl_cffi/requests/cookies.py" <<'PY'
    import sys
    from pathlib import Path

    path = Path(sys.argv[1])
    source = path.read_text()
    expected = 'raise ValueError("Invalid curl cookie change record")'
    assert source.count(expected) == 1
    path.write_text(source.replace(expected, expected + "  # divergent", 1))
    PY
    if (cd "$cookie_divergent" && bash -e "$transition_hook") >"$TMPDIR/cookie-divergence.log" 2>&1; then
      echo "cookie backport accepted divergent source" >&2
      exit 1
    fi
    grep -F "curl-cffi backport neither applies nor reverses cleanly" "$TMPDIR/cookie-divergence.log" >/dev/null

    tls_divergent="$TMPDIR/tls-divergent"
    cp -R "$source_root" "$tls_divergent"
    chmod -R u+w "$tls_divergent"
    python - "$tls_divergent/tests/unittest/test_curl.py" <<'PY'
    import sys
    from pathlib import Path

    path = Path(sys.argv[1])
    source = path.read_text()
    expected = "assert exc_info.value.code == CurlECode.PEER_FAILED_VERIFICATION"
    assert source.count(expected) == 1
    path.write_text(source.replace(expected, expected + "  # divergent", 1))
    PY
    if (cd "$tls_divergent" && bash -e "$transition_hook") >"$TMPDIR/tls-divergence.log" 2>&1; then
      echo "TLS backport accepted divergent source" >&2
      exit 1
    fi
    grep -F "curl-cffi backport neither applies nor reverses cleanly" "$TMPDIR/tls-divergence.log" >/dev/null

    ${lib.optionalString configuredTransition ''
        cd "$TMPDIR"
        python - <<'PY'
      from http.server import BaseHTTPRequestHandler, HTTPServer
      from threading import Thread

      from curl_cffi import requests


      class CookieHandler(BaseHTTPRequestHandler):
          def do_GET(self):
              self.send_response(200)
              if self.path == "/set":
                  self.send_header("Set-Cookie", "foo=bar; Path=/")
                  self.send_header("Set-Cookie", "keep=present; Path=/")
              elif self.path == "/delete":
                  self.send_header("Set-Cookie", "foo=; Max-Age=0; Path=/")
              self.send_header("Content-Length", "0")
              self.end_headers()

          def log_message(self, _format, *_args):
              pass


      server = HTTPServer(("127.0.0.1", 0), CookieHandler)
      thread = Thread(target=server.serve_forever, daemon=True)
      thread.start()
      session = requests.Session()
      try:
          base_url = f"http://127.0.0.1:{server.server_port}"
          session.get(f"{base_url}/set", timeout=5)
          assert session.cookies["foo"] == "bar"
          assert session.cookies["keep"] == "present"
          session.get(f"{base_url}/delete", timeout=5)
          assert "foo" not in session.cookies
          assert session.cookies["keep"] == "present"
      finally:
          session.close()
          server.shutdown()
          thread.join()
          server.server_close()
      PY
    ''}

    touch "$out"
  ''
