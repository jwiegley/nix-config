self: super: {

hyperorg = with super; with python3Packages; buildPythonPackage rec {
  pname = "hyperorg";
  version = "a814c4bf5e";
  pyproject = true;

  src = fetchgit {
    url = "https://codeberg.org/buhtz/hyperorg.git";
    rev = "f9fc6a164cd94df4d146c69fc7e48aeb143afe16";
    sha256 = "0cr16p6z0spr9xdabw4da77hrsmn4dzvfxd15kllva8w28xqsbl6";
    # date = 2025-08-31T09:48:06+02:00;
  };

  patches = [
    ./emacs/patches/hyperorg.patch
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
