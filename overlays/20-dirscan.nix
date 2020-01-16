self: super: {

dirscan = with super; python2Packages.buildPythonPackage rec {
  pname = "dirscan";
  version = "2.0";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "dirscan";
    rev = "af018fb14b9802400ce279b886fb4d09f4940348";
    sha256 = "1ri48v9yk0x291wlw6ady46dc6zcb6j25dgnljbgdxaxqfbx743n";
    # date = 2018-12-09T20:47:59-08:00;
  };

  phases = [ "unpackPhase" "fixupPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin $out/libexec
    cp dirscan.py $out/libexec
    cp cleanup $out/bin
  '';

  fixupPhase = ''
    sed -i -e "s|/usr/bin/env python2\.7|${pkgs.python27}/bin/python|" dirscan.py
    sed -i -e "s|/usr/bin/env python2\.7|${pkgs.python27}/bin/python|" cleanup
  '';

  meta = {
    homepage = https://github.com/jwiegley/dirscan;
    description = "Stateful directory scanning in Python";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
