self: super: {

git-subrepo = with super; stdenv.mkDerivation rec {
  name = "git-subrepo-${version}";
  version = "2f685964";

  src = fetchFromGitHub {
    owner = "ingydotnet";
    repo = "git-subrepo";
    rev = "2f6859642ae9104a9699021218bf607598f5a0ea";
    sha256 = "0gwm9x4kla4w9gb22pq6ffzi7mhmk550lfrpx1pyf8kb18kd9vmh";
    # date = 2020-11-25T19:55:46-06:00;
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
