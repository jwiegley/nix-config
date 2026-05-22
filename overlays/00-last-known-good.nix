# overlays/00-last-known-good.nix
# Purpose: Pin specific packages to known-good nixpkgs revisions
_final: prev:

let
  nixpkgs =
    args@{ rev, sha256 }:
    import (prev.fetchFromGitHub (
      args
      // {
        owner = "NixOS";
        repo = "nixpkgs";
      }
    )) { localSystem = prev.stdenv.hostPlatform.system; };

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
  lastGood = nixpkgs {
    rev = "b86751bc4085f48661017fa226dee99fab6c651b";
    sha256 = "sha256-a8BYi3mzoJ/AcJP8UldOx8emoPRLeWqALZWu4ZvjPXw=";
  };

  # Last good nixpkgs rev before nixpkgs PR 517610 (merged 2026-05-07)
  # bumped mesa 26.0.6 -> 26.1.0 without verifying Darwin builds. The new
  # mesa.aarch64-darwin output has no Hydra build / no cache.nixos.org entry,
  # and the new kosmickrisp Vulkan driver pulls in apple-sdk-26.0 + llvm-21
  # + SPIRV-LLVM-Translator-21, making a local rebuild slow and fragile.
  # Pin mesa together with its xorg-server/xquartz consumers so the closure
  # stays self-consistent. Drop these once Hydra is green on aarch64-darwin.
  preMesa26_1 = nixpkgs {
    rev = "f77951fcf0348ac9a4a5fc6c44c104d1387042d4";
    sha256 = "071sf9pckmxxwgpgx5jp2snjiq5bj5xm5vqfhhsvk82ad01azrw7";
  };
in
{
  # Meta/Facebook C++ libraries must be pinned together for closure
  # consistency: fbthrift links against folly headers, watchman pulls in
  # fizz/mvfst/wangle/edencommon, etc. Mixing old folly with new fizz makes
  # every fizz test fail at runtime (ABI mismatch).
  inherit (lastGood)
    ntp
    aprutil
    libcdio-paranoia
    folly
    fizz
    mvfst
    wangle
    fbthrift
    fb303
    edencommon
    watchman
    ;

  inherit (preMesa26_1)
    mesa
    xorg-server
    xquartz
    ;

  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (
      pfinal: pprev:
      (prev.lib.optionalAttrs (pprev ? av) {
        inherit (lastGood.${pprev.python.pythonAttr}.pkgs) av;
      })
      // (prev.lib.optionalAttrs (pprev ? openai-whisper) {
        inherit (lastGood.${pprev.python.pythonAttr}.pkgs) openai-whisper;
      })
    )
  ];

  eask-cli = prev.buildNpmPackage rec {
    pname = "eask-cli";
    version = "0.12.9";
    src = prev.fetchFromGitHub {
      owner = "emacs-eask";
      repo = "cli";
      rev = version;
      hash = "sha256-jYdx+MYgUop01MzcKPxtm+ZW6lsy9eCqH00uQd8imRw=";
    };
    npmDepsHash = "sha256-Xj68un97I8xtAY3RXEq8PNC8ZOZ+NWg6SblnmKzHGMo=";
    dontBuild = true;
    meta = with prev.lib; {
      description = "CLI for building, running, testing, and managing your Emacs Lisp dependencies";
      homepage = "https://emacs-eask.github.io/";
      license = licenses.gpl3Plus;
      mainProgram = "eask";
    };
  };
}
