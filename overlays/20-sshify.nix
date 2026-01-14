self: super: {

  sshify = with super;
    stdenv.mkDerivation rec {
      name = "sshify-${version}";
      version = "a6fb0d52";

      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "sshify";
        rev = "a6fb0d529ec01158dd031431099b0ba8c8d64eb6";
        sha256 = "sha256-wl2BZhVIpIFrcReQrMbkbxkrPA7vKKdkPfAYo5IlbIs=";
        # date = 2018-01-27T17:11:59-08:00;
      };

      phases = [ "unpackPhase" "installPhase" ];

      installPhase = ''
        mkdir -p $out/bin
        cp -p sshify $out/bin
      '';

      meta = {
        homepage = "https://github.com/jwiegley/sshify";
        description =
          "A tool for installing SSH authorized_key on remote servers";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

}
