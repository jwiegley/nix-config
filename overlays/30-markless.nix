# overlays/30-markless.nix
# Purpose: markless - Terminal markdown viewer with image support
# Dependencies: Uses prev only
# Packages: markless
final: prev: {

  markless =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "markless";
      version = "0.9.29";

      src = fetchFromGitHub {
        owner = "jvanderberg";
        repo = "markless";
        tag = "v${version}";
        hash = "sha256-orjJ++948WEJ031c5Dcvmfyqw2JMRJRjoBsGU+A+B4w=";
      };

      cargoHash = "sha256-kMMglmIsc3HkCx24Zir3NtZitwrxYwa7FgLgAZ2/ffo=";

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
