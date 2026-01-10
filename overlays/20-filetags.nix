self: super: {

filetags = with super; with python3Packages; buildPythonPackage rec {
  pname = "filetags";
  version = "778a2de5";
  name = "${pname}-${version}";
  pyproject = false;

  src = fetchFromGitHub {
    owner = "novoid";
    repo = "filetags";
    rev = "778a2de5a0d59477dbea6a315891180419369680";
    sha256 = "sha256-d4NNBn+y5er8j2zv85bKUutn5XSBykGWfTtr1/XA4zE=";
    # date = "2025-09-15T13:27:03+02:00";
  };

  propagatedBuildInputs = [ 
    colorama clint
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp -p filetags/__init__.py $out/bin/filetags
    chmod +x $out/bin/filetags
  '';

  meta = {
    homepage = https://github.com/novoid/filetags;
    description = "Management of simple tags within file names.";
    license = lib.licenses.gpl3;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
