self: super: {

  git-pr = with super;
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

}
