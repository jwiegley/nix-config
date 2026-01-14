self: super: {

  org2tc = with super;
    stdenv.mkDerivation rec {
      name = "org2tc-${version}";
      version = "7d52a20";

      src = /Users/johnw/src/hours/org2tc;

      phases = [ "unpackPhase" "installPhase" ];

      installPhase = ''
        mkdir -p $out/bin
        cp -p org2tc $out/bin
      '';

      meta = with super.lib; {
        description = "Conversion utility from Org-mode to timeclock format";
        homepage = "https://github.com/jwiegley/org2tc";
        license = licenses.mit;
        maintainers = with maintainers; [ jwiegley ];
        platforms = platforms.unix;
      };
    };

}
