self: super: {

git-scripts = with self; stdenv.mkDerivation {
  name = "git-scripts";

  src = builtins.filterSource (path: type:
      type != "directory" || baseNameOf path != ".git")
    ~/src/git-scripts;

  buildInputs = [];

  installPhase = ''
    mkdir -p $out/bin
    find . -maxdepth 1 \( -type f -o -type l \) -executable \
        -exec cp -pL {} $out/bin \;
  '';

  meta = with stdenv.lib; {
    description = "John Wiegley's various scripts";
    homepage = https://github.com/jwiegley;
    license = licenses.mit;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.darwin;
  };
};

}
