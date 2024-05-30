self: super: {

filetags = with super; with python3Packages; buildPythonPackage rec {
  pname = "filetags";
  version = "20240113";
  name = "${pname}-${version}";
  pyproject = false;

  src = fetchFromGitHub {
    owner = "novoid";
    repo = "filetags";
    rev = "a7f4d58998e02f53578c9d2dec73f30b5880fc1a";
    sha256 = "1n97aa12sdjvqav5h7bz72kw0hfx8qmhhqxb80yki1vfavin62bk";
    # date = "2024-01-13T18:29:31+01:00";
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
