self: super: {

teleport-kvm = with super; stdenv.mkDerivation rec {
  name = "teleport-${version}";
  version = "1.2.1";

  src = fetchFromGitHub {
    owner = "abyssoft";
    repo = "teleport";
    rev = "9a1e82a80486928084a2a0345352572fe779e179";
    sha256 = "07w3d2iy3wpn6z3z462p8qylm4dl9xn436lfhsghsncqc362yyv1";
    # date = 2016-05-25T23:45:48-07:00;
  };

  buildPhase = "xcodebuild";

  meta = {
    homepage = https://github.com/jwiegley/sift;
    description = "A tool for sifting apart large patch files";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
