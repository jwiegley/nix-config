self: super: {

pass-git-helper = with super; with python3Packages; buildPythonPackage rec {
  pname = "pass-git-helper";
  version = "0.4-1";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "languitar";
    repo = "pass-git-helper";
    rev = "0d7712f4bb1ade0dfec1816aff40334929771c08";
    sha256 = "1nw8ziy6f5ahj41ibcnp6z4aq23f43p3bij2fp5zk3gggcd5mzvh";
    # date = 2018-01-24T11:45:18+01:00;
  };

  buildInputs = [ pyxdg ];

  meta = {
    homepage = https://github.com/languitar/pass-git-helper;
    description = "A git credential helper interfacing with pass, the standard unix password manager";
    license = lib.licenses.lgpl3;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
