self: super: {

hyperorg = with super; with python3Packages; buildPythonPackage rec {
  pname = "hyperorg";
  version = "a814c4bf5e";
  pyproject = true;

  src = fetchgit {
    url = "https://codeberg.org/buhtz/hyperorg.git";
    rev = "a814c4bf5e95bd522fabe66d7baed9d71a7090e9";
    sha256 = "1zw9ha79g8qb2gg83hkpigaarsfvkz948mrjksfgbh5im4n7qykp";
    # date = 2024-08-25T21:16:09+02:00;
  };

  patches = [
    ./hyperorg.patch
  ];

  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    setuptools
    orgparse
    dateutil
    packaging
    requests
  ];

  meta = {
    homepage = https://codeberg.org/buhtz/hyperorg;
    description = "Hyperorg converts org-files and especially orgroam-v2-files into html-files.";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
