self: super: {

pass-git-helper = with super; with python3Packages; buildPythonPackage rec {
 pname = "pass-git-helper";
  version = "4.0.0";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "languitar";
    repo = "pass-git-helper";
    rev = "67cb6bbc01a60f1487fe43035e93b06b0656c0a5";
    sha256 = "1akdqh14w8yn3r6ijdfi2ljp7z3r2y5jxk61h0v9mpd0i0mpalr4";
    # date = 2025-10-02T16:40:46+02:00;
  };

  buildInputs = [ pyxdg pytest ];

  pythonPath = [ pyxdg pytest ];
  doCheck = false;

  pyproject = true;
  build-system = [ setuptools ];

  meta = {
    homepage = https://github.com/languitar/pass-git-helper;
    description = "A git credential helper interfacing with pass, the standard unix password manager";
    license = lib.licenses.lgpl3;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
