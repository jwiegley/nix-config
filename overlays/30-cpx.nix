# overlays/30-cpx.nix
# Purpose: cpx - Modern, fast file copy tool with progress bars and resume support
# Dependencies: prev plus tools source catalog; Linux only
# Packages: cpx
_final: prev:
let
  source = (import ../packages/source-catalog.nix "tools").cpx;
in
{
  cpx =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "cpx";
      inherit (source) version;

      src =
        assert source.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub source.source.args;

      cargoHash = source.hashes.cargoHash;

      # Keep the attribute reachable on Darwin for dependent-hash updates;
      # normal package selection remains Linux-only.
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
