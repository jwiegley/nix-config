self: super: {

yamale = with super; with python3Packages; buildPythonPackage rec {
  pname = "yamale";
  version = "c203d14b";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "23andMe";
    repo = "Yamale";
    rev = "c203d14bface6f35693874a8e4ee39079bcb9094";
    sha256 = "sha256-/Ax6EYZH8SEWJ2RIGOW7cotuALDaG/w/4twsXG+VSTw=";
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
