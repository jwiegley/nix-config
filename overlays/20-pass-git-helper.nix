self: super: {

pass-git-helper = with super; with python3Packages; buildPythonPackage rec {
 pname = "pass-git-helper";
  version = "2.0.0";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "languitar";
    repo = "pass-git-helper";
    rev = "cdcf24de34cab16071e25f2d2ffccd4bf8c55bf8";
    sha256 = "07cfz8qj5vnmqdjqxayw4v6sb200gxd08i0a7r3zkpjl4grnl68d";
    # date = 2024-06-18T19:04:24+02:00;
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
