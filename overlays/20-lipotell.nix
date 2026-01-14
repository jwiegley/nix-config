self: super: {

  lipotell = with super;
    stdenv.mkDerivation rec {
      name = "lipotell-${version}";
      version = "1502a475";

      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "lipotell";
        rev = "1502a4753f42618efcf2d0d561c818af377b0d92";
        sha256 = "sha256-TnaiGFXRzc4hwSgKvmxHJcCQW6H9Qh7VWQL+RoFb024=";
        # date = 2011-09-10T18:57:01-05:00;
      };

      phases = [ "unpackPhase" "installPhase" ];

      installPhase = ''
        mkdir -p $out/bin
        cp -p lipotell $out/bin
      '';

      meta = {
        homepage = "https://github.com/jwiegley/lipotell";
        description = "A tool to find large files within a directory";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

}
