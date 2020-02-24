self: super: {

yamale = with super; with python2Packages; buildPythonPackage rec {
  pname = "yamale";
  version = "618289c0";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "23andMe";
    repo = "Yamale";
    rev = "618289c07424ca34892f367d356cb993af69c406";
    sha256 = "0wsqbdnz4179l07mmdc3w1ci1b9mm0vvab6n0333qpllzqcazqxb";
    # date = 2020-02-07T13:03:39-05:00;
  };

  propagatedBuildInputs = [ pyyaml ];
  buildInputs = [ pytest ];

  meta = {
    homepage = https://github.com/23andMe/Yamale;
    description = "A schema and validator for YAML";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
