self: super: {

dirscan = with super; python2Packages.buildPythonPackage rec {
  pname = "dirscan";
  version = "2.0";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "dirscan";
    rev = "4646aac029f916381671409cc4c7419ae1894153";
    sha256 = "0iss4fsl43k4hvamyv60bh304pjji9pimwbzcanwk7rj9py4wf64";
    # date = 2018-11-10T09:44:46-08:00;
  };

  phases = [ "unpackPhase" "buildPhase" "installPhase" ];

  buildPhase = ''
    sed -i -e "s|/usr/bin/env python2\.7|${pkgs.python27}/bin/python|" dirscan.py
    sed -i -e "s|/usr/bin/env python2\.7|${pkgs.python27}/bin/python|" cleanup
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
