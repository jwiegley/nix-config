self: super: {

  nix-scripts = with self;
    stdenv.mkDerivation {
      name = "nix-scripts";

      src = ../bin;

      buildInputs = [ ];

      installPhase = ''
        mkdir -p $out/bin
        find . -maxdepth 1 \( -type f -o -type l \) -executable \
            -exec cp -pL {} $out/bin \;
      '';

      meta = with super.lib; {
        description = "John Wiegley's various scripts";
        homepage = "https://github.com/jwiegley";
        license = licenses.mit;
        maintainers = with maintainers; [ jwiegley ];
        platforms = platforms.darwin;
      };
    };

}
