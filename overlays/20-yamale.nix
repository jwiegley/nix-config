self: super: {

yamale = with super; with python2Packages; buildPythonPackage rec {
  pname = "yamale";
  version = "8d8e4b80";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "23andMe";
    repo = "Yamale";
    rev = "8d8e4b809c9e313795ac5c3721697ac853bfada5";
    sha256 = "1zdqw3s0268nli8yxsxymsjimf7izhimpsn45ci9y15gz87amgc8";
    # date = 2020-01-06T09:08:24-08:00;
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
