# overlays/00-last-known-good.nix
# Purpose: Pin specific packages to known-good nixpkgs revisions
_final: prev:

let
  sources = import ../packages/source-catalog.nix "compatibility";
  nixpkgs =
    name:
    let
      source = sources.${name}.source;
    in
    assert source.fetcher == "fetchTree";
    import (builtins.fetchTree source.args).outPath {
      localSystem = prev.stdenv.hostPlatform.system;
    };
  # Last good nixpkgs rev before the 2026-04-23 bump (rev 01fbdeef...)
  # broke several Darwin builds:
  #   - ntp: configure can't find pthreads on Darwin SDK 14.4
  #   - aprutil: sdbm_pair.c K&R decls rejected by clang C23 defaults
  #   - libcdio-paranoia: ./getopt.h K&R decl conflicts with unistd.h
  #   - python3Packages.av: pythonImportsCheckPhase OOMs loading ffmpeg syms
  #   - python3Packages.openai-whisper: ffmpeg-subprocess test fails in sandbox
  #   - folly: UninitializedMemoryHacksTest.cpp.o fails to compile with
  #     `__sanitizer_annotate_contiguous_container` undeclared under
  #     clang-21 + libc++ in SDK 14.4 (regression in folly 2026.01.19.00)
  lastGood = nixpkgs "nixpkgs-last-good";

in
{
  # Only ntp still fails to build against current nixpkgs (configure cannot
  # find pthreads on the Darwin SDK). aprutil, libcdio-paranoia and the whole
  # Meta/Facebook C++ set — folly, fizz, mvfst, wangle, fbthrift, fb303,
  # edencommon, watchman — build unpinned again and were released here on
  # 2026-08-01; `make pin-currency` reports when that changes.
  #
  # Those C++ libraries had to move together, since fbthrift links against
  # folly headers and watchman pulls in fizz/mvfst/wangle/edencommon. Mixing
  # old folly with new fizz makes every fizz test fail at runtime (ABI
  # mismatch), so releasing the set as a unit is what keeps the closure
  # self-consistent.
  inherit (lastGood)
    ntp
    ;

  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (
      _pfinal: pprev:
      (prev.lib.optionalAttrs (pprev ? av) {
        inherit (lastGood.${pprev.python.pythonAttr}.pkgs) av;
      })
      // (prev.lib.optionalAttrs (pprev ? openai-whisper) {
        inherit (lastGood.${pprev.python.pythonAttr}.pkgs) openai-whisper;
      })
    )
  ];

}
