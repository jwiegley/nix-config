{
  configured,
  lib,
  runCommand,
}:

let
  overlay = import ../../overlays/15-python-fixes.nix;

  fakeCurlCffi =
    {
      NIX_LDFLAGS ? null,
      envNixLdflags ? null,
      version,
      postPatch ? "",
    }:
    let
      old = {
        inherit postPatch version;
        patches = [ "existing.patch" ];
        passthru = { };
      }
      // lib.optionalAttrs (NIX_LDFLAGS != null) { inherit NIX_LDFLAGS; }
      // lib.optionalAttrs (envNixLdflags != null) {
        env.NIX_LDFLAGS = envNixLdflags;
      };
    in
    old
    // {
      overridePythonAttrs = transform: old // transform old;
    };

  evaluate =
    {
      curlCffiVersion,
      curlImpersonateVersion,
      finalCurlImpersonateVersion ? curlImpersonateVersion,
      isDarwin ? false,
      oldEnvNixLdflags ? null,
      oldNixLdflags ? null,
      oldPostPatch ? "",
    }:
    let
      fakeCurlImpersonate =
        version:
        let
          outPath = "/nix/store/00000000000000000000000000000000-curl-impersonate-${version}";
        in
        {
          out = outPath;
          inherit outPath version;
          outputs = [ "out" ];
        };
      prev = {
        inherit lib;
        curl-impersonate = fakeCurlImpersonate curlImpersonateVersion;
        pythonPackagesExtensions = [ ];
        stdenv.hostPlatform = { inherit isDarwin; };
      };
      final = prev // {
        curl-impersonate = fakeCurlImpersonate finalCurlImpersonateVersion;
      };
      extension = builtins.head (overlay final prev).pythonPackagesExtensions;
    in
    extension null {
      curl-cffi = fakeCurlCffi {
        NIX_LDFLAGS = oldNixLdflags;
        envNixLdflags = oldEnvNixLdflags;
        version = curlCffiVersion;
        postPatch = oldPostPatch;
      };
    };

  transitional = evaluate {
    curlCffiVersion = "0.15.0";
    curlImpersonateVersion = "2.1.0";
  };
  darwinTransitional = evaluate {
    curlCffiVersion = "0.15.0";
    curlImpersonateVersion = "2.1.0";
    isDarwin = true;
  };
  darwinInheritedNixLdflags = evaluate {
    curlCffiVersion = "0.15.0";
    curlImpersonateVersion = "2.1.0";
    isDarwin = true;
    oldNixLdflags = "-dead_strip";
  };
  darwinInheritedNixLdflagsList = evaluate {
    curlCffiVersion = "0.15.0";
    curlImpersonateVersion = "2.1.0";
    isDarwin = true;
    oldNixLdflags = [
      "-dead_strip"
      "-headerpad_max_install_names"
    ];
  };
  darwinInheritedEnvNixLdflags = evaluate {
    curlCffiVersion = "0.15.0";
    curlImpersonateVersion = "2.1.0";
    isDarwin = true;
    oldEnvNixLdflags = "-dead_strip";
  };
  darwinIntegratedRpath = evaluate {
    curlCffiVersion = "0.15.0";
    curlImpersonateVersion = "2.1.0";
    isDarwin = true;
    oldNixLdflags = "-dead_strip -rpath /nix/store/00000000000000000000000000000000-curl-impersonate-2.1.0/lib";
  };
  finalTransitionFromEarlierPrev = evaluate {
    curlCffiVersion = "0.15.0";
    curlImpersonateVersion = "1.5.6";
    finalCurlImpersonateVersion = "2.1.0";
    isDarwin = true;
  };
  finalEarlierFromTransitionalPrev = evaluate {
    curlCffiVersion = "0.15.0";
    curlImpersonateVersion = "2.1.0";
    finalCurlImpersonateVersion = "1.5.6";
    isDarwin = true;
  };
  earlierImpersonate = evaluate {
    curlCffiVersion = "0.15.0";
    curlImpersonateVersion = "1.5.6";
    isDarwin = true;
  };
  futureCurlCffi = evaluate {
    curlCffiVersion = "0.16.0";
    curlImpersonateVersion = "2.1.0";
    isDarwin = true;
  };
  inheritedPostPatch = evaluate {
    curlCffiVersion = "0.15.0";
    curlImpersonateVersion = "2.1.0";
    oldPostPatch = "printf '%s' inherited-post-patch > \"$TMPDIR/inherited-post-patch\"";
  };

  configuredCurlCffi = configured.python3Packages.curl-cffi;
  configuredVersion = configuredCurlCffi.version or "";
  configuredTransition =
    configuredVersion == "0.15.0" && (configured.curl-impersonate.version or "") == "2.1.0";
  configuredIntegrated = configuredVersion == "0.16.0";
  configuredSupported = configuredTransition || configuredIntegrated;
  configuredPostPatch = configuredCurlCffi.postPatch or "";
  configuredPython = configured.python3.withPackages (pythonPackages: [ pythonPackages.curl-cffi ]);
  configuredCurlRpath = "${lib.getLib configured.curl-impersonate}/lib";
  configuredNixLdflags =
    if configuredCurlCffi ? NIX_LDFLAGS then
      builtins.toString configuredCurlCffi.NIX_LDFLAGS
    else
      builtins.toString ((configuredCurlCffi.env or { }).NIX_LDFLAGS or "");
  configuredNixLdflagTokens = lib.filter (token: token != "") (
    lib.splitString " " configuredNixLdflags
  );
  hasConfiguredCurlRpath =
    remaining:
    builtins.length remaining >= 2
    && (
      (
        builtins.head remaining == "-rpath"
        && builtins.head (builtins.tail remaining) == configuredCurlRpath
      )
      || hasConfiguredCurlRpath (builtins.tail remaining)
    );
in
assert transitional.curl-cffi.patches == [ "existing.patch" ];
assert transitional.curl-cffi.passthru.nixConfigCurlCffiTransitionOwner;
assert lib.hasInfix "curl-cffi-0.15-cookie-changes.patch" transitional.curl-cffi.postPatch;
assert lib.hasInfix "curl-cffi-0.15-test-port.patch" transitional.curl-cffi.postPatch;
assert lib.hasInfix "curl-cffi-0.15-tls-error-codes.patch" transitional.curl-cffi.postPatch;
assert lib.hasInfix "curl-cffi-0.15-websocket-partial-send.patch" transitional.curl-cffi.postPatch;
assert !(transitional.curl-cffi ? NIX_LDFLAGS);
assert
  darwinTransitional.curl-cffi.NIX_LDFLAGS
  == "-rpath /nix/store/00000000000000000000000000000000-curl-impersonate-2.1.0/lib";
assert
  darwinInheritedNixLdflags.curl-cffi.NIX_LDFLAGS
  == "-dead_strip -rpath /nix/store/00000000000000000000000000000000-curl-impersonate-2.1.0/lib";
assert
  darwinInheritedNixLdflagsList.curl-cffi.NIX_LDFLAGS
  == "-dead_strip -headerpad_max_install_names -rpath /nix/store/00000000000000000000000000000000-curl-impersonate-2.1.0/lib";
assert !(darwinInheritedEnvNixLdflags.curl-cffi ? NIX_LDFLAGS);
assert
  darwinInheritedEnvNixLdflags.curl-cffi.env.NIX_LDFLAGS
  == "-dead_strip -rpath /nix/store/00000000000000000000000000000000-curl-impersonate-2.1.0/lib";
assert
  darwinIntegratedRpath.curl-cffi.NIX_LDFLAGS
  == "-dead_strip -rpath /nix/store/00000000000000000000000000000000-curl-impersonate-2.1.0/lib";
assert
  finalTransitionFromEarlierPrev.curl-cffi.NIX_LDFLAGS
  == "-rpath /nix/store/00000000000000000000000000000000-curl-impersonate-2.1.0/lib";
assert lib.hasInfix "curl-cffi-0.15-cookie-changes.patch"
  finalTransitionFromEarlierPrev.curl-cffi.postPatch;
assert finalEarlierFromTransitionalPrev.curl-cffi.postPatch == "";
assert !(finalEarlierFromTransitionalPrev.curl-cffi ? NIX_LDFLAGS);
assert earlierImpersonate.curl-cffi.patches == [ "existing.patch" ];
assert earlierImpersonate.curl-cffi.passthru.nixConfigCurlCffiTransitionOwner;
assert earlierImpersonate.curl-cffi.postPatch == "";
assert !(earlierImpersonate.curl-cffi ? NIX_LDFLAGS);
assert !(lib.hasInfix "curl-cffi-0.15-cookie-changes.patch" earlierImpersonate.curl-cffi.postPatch);
assert
  !(lib.hasInfix "curl-cffi-0.15-tls-error-codes.patch" earlierImpersonate.curl-cffi.postPatch);
assert futureCurlCffi.curl-cffi.patches == [ "existing.patch" ];
assert futureCurlCffi.curl-cffi.postPatch == "";
assert !(futureCurlCffi.curl-cffi ? NIX_LDFLAGS);
assert lib.hasInfix "\"$TMPDIR/inherited-post-patch\"\n_nix_config_apply_curl_backport"
  inheritedPostPatch.curl-cffi.postPatch;
assert configuredSupported || throw "unsupported curl-cffi transition state ${configuredVersion}";
assert
  !configuredTransition || (configuredCurlCffi.passthru.nixConfigCurlCffiTransitionOwner or false);
assert
  !configuredIntegrated || !(configuredCurlCffi.passthru.nixConfigCurlCffiTransitionOwner or false);
assert !configuredIntegrated || !(lib.hasInfix "curl-cffi-0.15-" configuredPostPatch);
assert
  !configuredTransition
  || (
    lib.hasInfix "curl-cffi-0.15-cookie-changes.patch" configuredPostPatch
    && lib.hasInfix "curl-cffi-0.15-test-port.patch" configuredPostPatch
    && lib.hasInfix "curl-cffi-0.15-tls-error-codes.patch" configuredPostPatch
    && lib.hasInfix "curl-cffi-0.15-websocket-partial-send.patch" configuredPostPatch
  );
assert
  !configuredTransition
  || !configured.stdenv.hostPlatform.isDarwin
  || hasConfiguredCurlRpath configuredNixLdflagTokens;
runCommand "python-package-fixes-tests"
  (
    {
      nativeBuildInputs = [
        configuredPython
      ]
      ++ lib.optionals (configuredTransition && configured.stdenv.hostPlatform.isDarwin) [
        configured.stdenv.cc.bintools
      ];
    }
    // lib.optionalAttrs configuredSupported {
      __darwinAllowLocalNetworking = true;
    }
  )
  ''
    source_root="$TMPDIR/curl-cffi-source"
    cp -R ${configuredCurlCffi.src} "$source_root"
    chmod -R u+w "$source_root"
    # Importing the installed extension is the production loadability check:
    # it fails here if its @rpath curl-impersonate dependency is unresolved.
    installed_wrapper="$(python -c 'import curl_cffi._wrapper; print(curl_cffi._wrapper.__file__)')"
    cp "$installed_wrapper" "$source_root/curl_cffi/"

    ${lib.optionalString (configuredTransition && configured.stdenv.hostPlatform.isDarwin) ''
      dependencies="$(otool -L "$installed_wrapper")"
      grep -F $'\t@rpath/libcurl-impersonate.4.dylib ' <<<"$dependencies" >/dev/null
      load_commands="$(otool -l "$installed_wrapper")"
      rpath_count="$(awk -v expected=${lib.escapeShellArg configuredCurlRpath} '
        $1 == "cmd" { in_rpath = ($2 == "LC_RPATH"); next }
        in_rpath && $1 == "path" {
          if ($2 == expected) count++
          in_rpath = 0
        }
        END { print count + 0 }
      ' <<<"$load_commands")"
      test "$rpath_count" = 1
    ''}

    if ${lib.boolToString configuredTransition}; then
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
      bash -e "$inherited_hook"
      test "$(cat "$TMPDIR/inherited-post-patch")" = inherited-post-patch
      bash -e "$transition_hook"
    test "$(grep -Fc 'port=0' tests/unittest/conftest.py)" = 2
    grep -F 'thread = threading.Thread(target=server.run, daemon=True)' tests/unittest/conftest.py >/dev/null
    grep -F 'deadline = time.monotonic() + timeout' tests/unittest/conftest.py >/dev/null
    grep -F 'if not thread.is_alive():' tests/unittest/conftest.py >/dev/null
    grep -F 'if thread.is_alive() and not failed:' tests/unittest/conftest.py >/dev/null
    grep -F 'server.config.port = sockets[0].getsockname()[1]' tests/unittest/conftest.py >/dev/null
    ! grep -F '8000' tests/unittest/test_curl.py >/dev/null
    ! grep -F '8000' tests/unittest/test_requests.py >/dev/null
    grep -F 'url = f"http://example.com:{port}"' tests/unittest/test_curl.py >/dev/null
    grep -F 'assert r.primary_port == server.config.port' tests/unittest/test_requests.py >/dev/null
    grep -F 'frame_end: int = 0' curl_cffi/requests/websockets.py >/dev/null
    grep -F 'curl_ws_send(view[offset:frame_end], current_flags)' curl_cffi/requests/websockets.py >/dev/null
    grep -F 'async def test_partial_write_exact_boundary_resumption() -> None:' tests/unittest/test_async_websocket_partial_send.py >/dev/null
    grep -F '(55536, 55536, int(CurlWsFlag.BINARY | CurlWsFlag.CONT)),' tests/unittest/test_async_websocket_partial_send.py >/dev/null

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
    # preimage nor the exact postimage. The mutations below prove the shared
    # patch gate rejects that state instead of hiding divergent integration.
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

    port_divergent="$TMPDIR/port-divergent"
    cp -R "$source_root" "$port_divergent"
    chmod -R u+w "$port_divergent"
    python - "$port_divergent/tests/unittest/conftest.py" <<'PY'
    import sys
    from pathlib import Path

    path = Path(sys.argv[1])
    source = path.read_text()
    expected = "server.config.port = sockets[0].getsockname()[1]"
    assert source.count(expected) == 1
    path.write_text(source.replace(expected, expected + "  # divergent", 1))
    PY
    if (cd "$port_divergent" && bash -e "$transition_hook") >"$TMPDIR/port-divergence.log" 2>&1; then
      echo "test-port backport accepted divergent source" >&2
      exit 1
    fi
    grep -F "curl-cffi backport neither applies nor reverses cleanly" "$TMPDIR/port-divergence.log" >/dev/null

    websocket_divergent="$TMPDIR/websocket-divergent"
    cp -R "$source_root" "$websocket_divergent"
    chmod -R u+w "$websocket_divergent"
    python - "$websocket_divergent/curl_cffi/requests/websockets.py" <<'PY'
    import sys
    from pathlib import Path

    path = Path(sys.argv[1])
    source = path.read_text()
    expected = "frame_end: int = 0"
    assert source.count(expected) == 1
    path.write_text(source.replace(expected, expected + "  # divergent", 1))
    PY
    if (cd "$websocket_divergent" && bash -e "$transition_hook") >"$TMPDIR/websocket-divergence.log" 2>&1; then
      echo "WebSocket backport accepted divergent source" >&2
      exit 1
    fi
    grep -F "curl-cffi backport neither applies nor reverses cleanly" "$TMPDIR/websocket-divergence.log" >/dev/null
    fi

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

    touch "$out"
  ''
