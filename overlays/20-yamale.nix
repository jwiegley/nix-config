self: super: {

yamale = with super; with python3Packages; buildPythonPackage rec {
  pname = "yamale";
  version = "4726dcf1";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "23andMe";
    repo = "Yamale";
    rev = "4726dcf174a09c90908a92dbd787260c83391e9c";
    sha256 = "06a7lhkh9k5a212h29b8dy2vw669g9f4c5hml42ajl1zhdzfq5jy";
    # date = 2025-10-27T13:56:16-04:00;
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
