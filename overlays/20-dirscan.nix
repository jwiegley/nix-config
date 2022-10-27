self: super: {

dirscan = with super; python2Packages.buildPythonPackage rec {
  pname = "dirscan";
  version = "2.0";
  format = "source";

  src = ~/src/dirscan;

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
