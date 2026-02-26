# overlays/30-markless.nix
# Purpose: markless - Terminal markdown viewer with image support
# Dependencies: Uses prev only
# Packages: markless
final: prev: {

  markless =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "markless";
      version = "0.9.16";

      src = fetchFromGitHub {
        owner = "jvanderberg";
        repo = "markless";
        tag = "v${version}";
        hash = "sha256-jqHFZQDFuASilUSjYXrw8pUBgWFEk/qoFi37bPXsnxo=";
      };

      cargoHash = "sha256-okrUPy4i1KDx1A4F3T+R157JWypyWAJrXo9OyYS+MyI=";

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
