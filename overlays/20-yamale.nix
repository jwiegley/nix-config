self: super: {

yamale = with super; with python2Packages; buildPythonPackage rec {
  pname = "yamale";
  version = "edb7ea";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "23andMe";
    repo = "Yamale";
    rev = "edb7ea4972fc8420e4470907dc60967cb91ad9bb";
    sha256 = "0z9x2iq9k50gj218g0wady0r0l8rdz8sli2wsfl7rsm07cbvi0qq";
    # date = 2017-07-25T13:55:59-07:00;
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
