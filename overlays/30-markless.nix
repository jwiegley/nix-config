# overlays/30-markless.nix
# Purpose: markless - Terminal markdown viewer with image support
# Dependencies: Uses prev only
# Packages: markless
_final: prev:
let
  source = (import ../packages/source-catalog.nix "tools").markless;
in
{

  markless =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "markless";
      inherit (source) version;

      src =
        assert source.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub source.source.args;

      cargoHash = source.hashes.cargoHash;

      doCheck = false;

      meta = with lib; {
        description = "A terminal markdown viewer with image support";
        homepage = "https://github.com/jvanderberg/markless";
        license = licenses.mit;
        maintainers = with maintainers; [ jwiegley ];
        mainProgram = "markless";
      };
    };

}
