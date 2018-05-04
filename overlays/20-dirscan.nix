self: super: {

dirscan = with super; python2Packages.buildPythonPackage rec {
  pname = "dirscan";
  version = "2.0";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "dirscan";
    rev = "794a6a7f1076878bc10671619cb92eac7765617d";
    sha256 = "11pzv5d9jb08jjw36di2951c4dnmsvf9kvmg3vnikd3p7zlg62hy";
    # date = 2018-01-28T01:23:09-08:00;
  };

  phases = [ "unpackPhase" "buildPhase" "installPhase" ];

  buildPhase = ''
    sed -i -e "s|/usr/bin/env python|${pkgs.python27}/bin/python|" dirscan.py
    sed -i -e "s|/usr/bin/env python2.7|${pkgs.python27}/bin/python|" cleanup
    sed -i -e "s|/Users/johnw/bin/dirscan|$out/libexec|" cleanup
  '';

  installPhase = ''
    mkdir -p $out/bin $out/libexec
    cp dirscan.py $out/libexec
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
