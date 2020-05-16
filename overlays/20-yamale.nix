self: super: {

yamale = with super; with python2Packages; buildPythonPackage rec {
  pname = "yamale";
  version = "618289c0";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "23andMe";
    repo = "Yamale";
    rev = "21926d6cd53a68eac461e7c15e61757ee8d46838";
    sha256 = "0nnhp8lwaix83bv327sp3cgw4spb7s0ind5yg8k8nmij3rgfnvvl";
    # date = 2020-05-09T14:28:28-07:00;
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
