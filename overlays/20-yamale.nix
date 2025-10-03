self: super: {

yamale = with super; with python3Packages; buildPythonPackage rec {
  pname = "yamale";
  version = "c989fabf";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "23andMe";
    repo = "Yamale";
    rev = "c989fabfb2813885c5355f5f8bbf06ca02847e40";
    sha256 = "15f0zbmsaddqad5zl8bd0xhpmqgx41jy8lgwcynl878qcf266gr2";
    # date = 2025-01-02T15:35:16-05:00;
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
