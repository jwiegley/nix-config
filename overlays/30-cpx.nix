# overlays/30-cpx.nix
# Purpose: cpx - Modern, fast file copy tool with progress bars and resume support
# Dependencies: Rust, Linux-specific (copy_file_range syscall)
# Packages: cpx
_final: prev:
let
  source = (import ../packages/source-catalog.nix "tools").cpx;
in
prev.lib.optionalAttrs prev.stdenv.isLinux {

  cpx =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "cpx";
      inherit (source) version;

      src =
        assert source.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub source.source.args;

      cargoHash = source.hashes.cargoHash;

      # cpx is currently Linux-only (uses copy_file_range syscall)
      # Skip build on Darwin
      meta = with lib; {
        description = "A modern, fast file copy tool for Linux with progress bars, resume capability, and more";
        homepage = "https://github.com/11happy/cpx";
        license = licenses.mit;
        maintainers = with maintainers; [ jwiegley ];
        platforms = platforms.linux;
        mainProgram = "cpx";
      };
    };

}
