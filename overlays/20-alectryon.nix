self: super: {

alectryon = with super; with python3Packages; buildPythonPackage rec {
  pname = "alectryon";
  version = "1.4.0";
  name = "${pname}-${version}";
  format = "pyproject";

  src = fetchFromGitHub {
    owner = "cpitclaudel";
    repo = "alectryon";
    rev = "739b46da22d272e748f60f3efcd2989d696fba71";
    sha256 = "10p57vkif119qsc156jrkr3f0fdc5hzh5ymxh3334f6gadzpxq4z";
  };

  propagatedNativeBuildInputs = [ 
    coqPackages_8_15.serapi 
  ];

  propagatedBuildInputs = [ 
    dominate pygments docutils 
    sphinx beautifulsoup4 
    # myst-parser
  ];
  buildInputs = [ pytest ];

  meta = {
    homepage = https://github.com/cpitclaudel/alectryon;
    description = ''
A collection of tools for writing technical documents that mix Coq code and prose.
'';
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
