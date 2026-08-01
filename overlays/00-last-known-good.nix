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

  # Last good nixpkgs rev before nixpkgs PR 517610 (merged 2026-05-07)
  # bumped mesa 26.0.6 -> 26.1.0 without verifying Darwin builds. The new
  # mesa.aarch64-darwin output has no Hydra build / no cache.nixos.org entry,
  # and the new kosmickrisp Vulkan driver pulls in apple-sdk-26.0 + llvm-21
  # + SPIRV-LLVM-Translator-21, making a local rebuild slow and fragile.
  # Pin mesa together with its xorg-server/xquartz consumers so the closure
  # stays self-consistent. Drop these once Hydra is green on aarch64-darwin.
  preMesa26_1 = nixpkgs "nixpkgs-pre-mesa-26-1";

  # Last good nixpkgs rev (== prior flake.lock pin, 2026-05-22) before the
  # 2026-05-25 nixpkgs bump (rev f9d8b659...) shipped rclone 1.74.2, which
  # unconditionally switched `buildInputs` from `macfuse-stubs` (Darwin) to
  # `fuse3` (Linux-only). The new derivation does not provide `fuse.h` on
  # Darwin, so cgofuse fails:
  #     vendor/.../cgofuse/fuse/host_cgo.go:119:10:
  #       fatal error: 'fuse.h' file not found
  # 1.74.1 from this rev still uses macfuse-stubs and builds cleanly on
  # aarch64-darwin. Drop this once nixpkgs restores the Darwin code path.
  preRcloneFuse3Break = nixpkgs "nixpkgs-pre-rclone-fuse3";

  # Last good nixpkgs rev (== prior flake.lock pin, 2026-07-02) before the
  # 2026-07-05 bump (rev 19a8a1e6...) shipped a nixos-render-docs that
  # removed the --toc-depth flag ("use --sidebar-depth instead"). nix-darwin
  # (a1fa429, currently upstream HEAD) still passes --toc-depth when
  # building darwin-manual-html, so the manual and darwin-help fail. Drop
  # this once nix-darwin switches to --sidebar-depth.
  preTocDepthRemoval = nixpkgs "nixpkgs-pre-toc-depth-removal";
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

  inherit (preMesa26_1)
    mesa
    xorg-server
    xquartz
    ;

  # Pin rclone (and thus its consumers via the overlay) until nixpkgs
  # restores Darwin fuse support. See `preRcloneFuse3Break` above.
  inherit (preRcloneFuse3Break)
    rclone
    ;

  # Pin nixos-render-docs until nix-darwin adapts to the removal of
  # --toc-depth. See `preTocDepthRemoval` above.
  inherit (preTocDepthRemoval)
    nixos-render-docs
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
