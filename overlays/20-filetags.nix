self: super: {

filetags = with super; with python3Packages; buildPythonPackage rec {
  pname = "filetags";
  version = "20240113";
  name = "${pname}-${version}";
  pyproject = false;

  src = fetchFromGitHub {
    owner = "novoid";
    repo = "filetags";
    rev = "b042bd20314898527c9c2a0d942c25d0b01c263f";
    sha256 = "1xkb5rha8f7zxgvwlk3gl6nba6jq74pgcnwg5m5kn59hra41f3kd";
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
