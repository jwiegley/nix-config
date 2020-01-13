self: super: {

pass-git-helper = with super; with python3Packages; buildPythonPackage rec {
 pname = "pass-git-helper";
  version = "1.1.0";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "languitar";
    repo = "pass-git-helper";
    rev = "561c464f896edebff6d9cf3722dcb299f300ab99";
    sha256 = "0nn475pqhywirdprla9ihyf7pz4pv5pfc5rvc09q602fv51zc6qs";
    # date = 2019-11-22T20:00:41+01:00;
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
