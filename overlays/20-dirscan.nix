self: super: {

dirscan = with super; python2Packages.buildPythonPackage rec {
  pname = "dirscan";
  version = "2.0";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "dirscan";
    rev = "97f391b4e18db7d04f6a7b15e6b53d8d5af11fe5";
    sha256 = "034wxjwp59f22165yvxki3kbjv747awqamxfwqvikhan7a5kwd8r";
    # date = 2020-01-21T15:46:19-08:00;
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin $out/libexec
    cp dirscan.py $out/libexec
    python -mpy_compile $out/libexec/dirscan.py
    cp cleanup $out/bin
  '';

  meta = {
    homepage = https://github.com/jwiegley/dirscan;
    description = "Stateful directory scanning in Python";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
