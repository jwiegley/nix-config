self: super: {

git-subrepo = with super; stdenv.mkDerivation rec {
  name = "git-subrepo-${version}";
  version = "a04d8c2e";

  src = fetchFromGitHub {
    owner = "ingydotnet";
    repo = "git-subrepo";
    rev = "a04d8c2e55c31931d66b5c92ef6d4fe4c59e3226";
    sha256 = "0n10qnc8kyms6cv65k1n5xa9nnwpwbjn9h2cq47llxplawzqgrvp";
    # date = 2020-01-09T17:28:02-06:00;
  };

  buildInputs = with self; [ which git ];

  preBuild = ''
    makeFlagsArray=(
      DESTDIR="$out"
      PREFIX=""
      INSTALL_LIB="$out/bin");
  '';

  meta = {
    homepage = https://github.com/ingydotnet/git-subrepo;
    description = ''
      git-subrepo "clones" an external git repo into a subdirectory of your
      repo. Later on, upstream changes can be pulled in, and local changes can
      be pushed back.
    '';
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
