self: super: {

yamale = with super; with python3Packages; buildPythonPackage rec {
  pname = "yamale";
  version = "bacaa1d8";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "23andMe";
    repo = "Yamale";
    rev = "bacaa1d8e20395e11fe087cb7a7cb0365c2afd50";
    sha256 = "0ac9j5rm0bgfkwmri131d8v16abyndfxx58lnnkmil1rkl0r0a4a";
    # date = 2024-04-30T16:14:31-04:00;
  };

  propagatedBuildInputs = [ pyyaml ];
  buildInputs = [ pytest ];

  pyproject = true;
  build-system = [ setuptools ];

  meta = {
    homepage = https://github.com/23andMe/Yamale;
    description = "A schema and validator for YAML";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
