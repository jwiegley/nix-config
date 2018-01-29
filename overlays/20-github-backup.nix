self: super: {

github-backup = with super; with python3Packages; buildPythonPackage rec {
  pname = "github-backup";
  version = "0.16.0";
  name = "${pname}-${version}";

  src = fetchFromGitHub {
    owner = "josegonzalez";
    repo = "github-backup";
    rev = "e59d1e3a682b67a3fc6cf2420f04eaec7c95a0f3";
    sha256 = "05rpxbjspx34rpxv75y8hd18bsdc7l2l0y5yix3gbgnf4rw9rv31";
    # date = 2018-01-22T12:49:31-05:00;
  };

  buildInputs = [ ];

  meta = {
    homepage = https://github.com/josegonzalez/python-github-backup;
    description = "Backup a GitHub user or organization";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
