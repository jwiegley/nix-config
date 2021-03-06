self: super: {

pass-git-helper = with super; with python3Packages; buildPythonPackage rec {
 pname = "pass-git-helper";
  version = "1.1.1";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "languitar";
    repo = "pass-git-helper";
    rev = "c9d1cad66760397e8759829e12392dcc88a6d505";
    sha256 = "19igwxgbj9q1mzibwd2isyipkpdmvbsrqrbghw5ag3skwfqyf2q0";
    # date = 2021-01-05T21:43:57+01:00;
  };

  buildInputs = [ pyxdg pytest ];

  pythonPath = [ pyxdg pytest ];
  doCheck = false;

  meta = {
    homepage = https://github.com/languitar/pass-git-helper;
    description = "A git credential helper interfacing with pass, the standard unix password manager";
    license = lib.licenses.lgpl3;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
