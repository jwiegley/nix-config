self: super: {

daiquiri = with super; with python3Packages; buildPythonPackage rec {
  pname = "daiquiri";
  version = "1.3.1.dev1";
  name = "${pname}-${version}";

  src = fetchurl {
    url = https://files.pythonhosted.org/packages/1c/75/3d035ab98ac77db6b8a5ee164113d02e7dfc2f2f7531493fcd314a9a8a7f/daiquiri-1.3.0.tar.gz;
    sha256 = "19ap9aylg0hwb0w4p0smgj72blklf7k3fcsw80hpz4rrdpy1lsy8";
    # date = 2018-04-29T20:52:56-0700;
  };

  buildInputs = [ six testtools ];

  doCheck = false;

  meta = {
    homepage = https://github.com/jd/daiquiri;
    description = "Python library to easily setup basic logging functionality";
    license = lib.licenses.apache2;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

pygithub = with super; with python3Packages; buildPythonPackage rec {
  pname = "PyGithub";
  version = "b0fc5d";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "PyGithub";
    repo = "PyGithub";
    rev = "b0fc5da5ae0cd1b90124ad45fe985080afe552e8";
    sha256 = "11jc6kfxay51hk1ipb7z49rrxqv93lqjws4mkp76yl65mjbvxak4";
    # date = 2018-04-26T14:52:47+08:00;
  };

  buildInputs = [ requests pyjwt ];

  meta = {
    homepage = https://github.com/PyGithub/PyGithub;
    description = "Typed interactions with the GitHub API v3";
    license = lib.licenses.lgpl3;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

git-pull-request = with super; with python3Packages; buildPythonPackage rec {
  pname = "git-pull-request";
  version = "2.5.0";
  name = "${pname}-${version}";

  src = fetchurl {
    url = https://files.pythonhosted.org/packages/8e/ea/0625f5beb17e78a75f59364a780dbdfa818fcfa1637949b3ab6f811b5c37/git-pull-request-2.5.0.tar.gz;
    sha256 = "072904x8jcisq71v7b54izvnm53m5jsz17v6in1p395qnyag9xla";
    # date = 2018-04-29T20:54:49-0700;
  };

  propagatedBuildInputs = [ self.pygithub self.daiquiri requests pyjwt fixtures git ];

  # doCheck = false;

  meta = {
    homepage = https://github.com/jd/git-pull-request;
    description = "Send git pull-request via command line";
    license = lib.licenses.apache2;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
