# overlays/30-markless.nix
# Purpose: markless - Terminal markdown viewer with image support
# Dependencies: Uses prev only
# Packages: markless
final: prev: {

  markless =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "markless";
      version = "0.9.24";

      src = fetchFromGitHub {
        owner = "jvanderberg";
        repo = "markless";
        tag = "v${version}";
        hash = "sha256-LLI2hCsuWBlD0UyAkEbl2pz9+EEfpqPdPxEa/a4R11c=";
      };

      cargoHash = "sha256-v0wl2d6JXkI/BVVZ2TQiNJmjeItkZIqj80wWUYlloUU=";

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
