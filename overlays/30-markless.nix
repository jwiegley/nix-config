# overlays/30-markless.nix
# Purpose: markless - Terminal markdown viewer with image support
# Dependencies: Uses prev only
# Packages: markless
final: prev: {

  markless =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "markless";
      version = "0.9.26";

      src = fetchFromGitHub {
        owner = "jvanderberg";
        repo = "markless";
        tag = "v${version}";
        hash = "sha256-b/aqmFh+hjA2h0Quw8aOvivtyxw2QCEZm5B4JrHxDuU=";
      };

      cargoHash = "sha256-qFwreG+v2bFuD6I85wQKuGR7Gdpl0NxUq/y8oO8kX3E=";

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
