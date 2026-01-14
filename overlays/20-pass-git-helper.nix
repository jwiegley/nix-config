self: super: {

  pass-git-helper = with super;
    with python3Packages;
    buildPythonPackage rec {
      pname = "pass-git-helper";
      version = "8832ffb0";
      name = "${pname}-${version}";

      src = fetchFromGitHub {
        owner = "languitar";
        repo = "pass-git-helper";
        rev = "8832ffb02520c45e879a6c98cb9696a712324fe3";
        sha256 = "sha256-3aYJaqIL+nFZm3XUqC2+CIed967U6yKVIwegsAtrWQg=";
        # date = 2025-10-02T16:40:46+02:00;
      };

      buildInputs = [ pyxdg pytest ];

      pythonPath = [ pyxdg pytest ];
      doCheck = false;

      pyproject = true;
      build-system = [ setuptools ];

      meta = {
        homepage = "https://github.com/languitar/pass-git-helper";
        description =
          "A git credential helper interfacing with pass, the standard unix password manager";
        license = lib.licenses.lgpl3;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

}
