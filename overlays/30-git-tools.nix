# overlays/30-git-tools.nix
# Purpose: Git-related tools and extensions
# Dependencies: None (uses only prev)
# Packages: git-lfs, git-pr, git-scripts
# Note: git-scripts requires paths.gitScripts
final: prev:

let paths = import ../config/paths.nix { inherit (prev) inputs; };
in {

  # Git Large File Storage (pre-built binary for darwin-arm64)
  git-lfs = with prev;
    stdenv.mkDerivation rec {
      name = "git-lfs-${version}";
      version = "3.7.0";

      src = fetchurl {
        url =
          "https://github.com/git-lfs/git-lfs/releases/download/v${version}/git-lfs-darwin-arm64-v${version}.zip";
        sha256 = "sha256-NMqd9wMQYbhHHVMHbLdql0dok3ognD/Ko95icOxkZeo=";
        # date = 2020-05-16T00:38:51-0800;
      };

      phases = [ "unpackPhase" "installPhase" ];

      buildInputs = [ unzip ];

      unpackPhase = ''
        unzip ${src}
      '';

      installPhase = ''
        mkdir -p $out/bin
        cp -p git-lfs-${version}/git-lfs $out/bin
      '';

      meta = with prev.lib; {
        description = "An open source Git extension for versioning large files";
        homepage = "https://git-lfs.github.com/";
        license = licenses.mit;
        maintainers = with maintainers; [ jwiegley ];
        platforms = platforms.unix;
      };
    };

  # Create and update GitHub PRs with stacked commits
  git-pr = with prev;
    buildGoModule rec {
      pname = "git-pr";
      version = "1.2.0";
      rev = "v${version}";

      vendorHash = "sha256-QzTSo4DbPMMiDCnLKQgkDPiCp1inc+QQhLpRiWCGnFM=";

      src = fetchFromGitHub {
        inherit rev;
        owner = "iOliverNguyen";
        repo = "git-pr";
        sha256 = "sha256-h5B7FLDNjf9YOx49vClc4ejc0XMziHzBXCo6eptVtRU=";
      };

      meta = {
        description =
          "git-pr is a command line tool to create and update GitHub pull requests within stacked commits";
        license = lib.licenses.mit;
        homepage = "https://github.com/iOliverNguyen/git-pr";
        maintainers = with lib.maintainers; [ jwiegley ];
        platforms = with lib.platforms; unix;
        mainProgram = "git-pr";
      };
    };

  # Custom git helper scripts
  # Note: Requires paths.gitScripts
  git-scripts = with prev;
    stdenv.mkDerivation {
      name = "git-scripts";

      src = paths.gitScripts;

      buildInputs = [ ];

      installPhase = ''
        mkdir -p $out/bin
        find . -maxdepth 1 \( -type f -o -type l \) -executable \
            -exec cp -pL {} $out/bin \;
      '';

      meta = with prev.lib; {
        description = "John Wiegley's git scripts";
        homepage = "https://github.com/jwiegley";
        license = licenses.mit;
        maintainers = with maintainers; [ jwiegley ];
        platforms = platforms.darwin;
      };
    };

}
