self: super: {

pass-git-helper = with super; with python3Packages; buildPythonPackage rec {
 pname = "pass-git-helper";
  version = "1.1.0";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "languitar";
    repo = "pass-git-helper";
    rev = "faceb47cccbb0d7b0330871f353bccb9b9ddd201";
    sha256 = "1gv78msx04hjvca3dixaj5dbvkmaak6qm0qgvqg9yb3hzjh1jbjl";
    # date = 2020-05-13T20:20:21+02:00;
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
