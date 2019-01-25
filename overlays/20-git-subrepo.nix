self: super: {

git-subrepo = with super; stdenv.mkDerivation rec {
  name = "git-subrepo-${version}";
  version = "32fbd76";

  src = fetchFromGitHub {
    owner = "ingydotnet";
    repo = "git-subrepo";
    rev = "5d6aba91dbff3157e498b0a795e99e2fcb7d9ec4";
    sha256 = "05m2dm9gq2nggwnxxdyq2kjj584sn2lxk66pr1qhjxnk81awj9l7";
    # date = 2018-11-08T12:59:08+01:00;
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
