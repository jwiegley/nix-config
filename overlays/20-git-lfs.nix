self: super: {

git-lfs = with super; stdenv.mkDerivation rec {
  name = "git-lfs-${version}";
  version = "2.11.0";

  src = fetchurl {
    url = "https://github.com/git-lfs/git-lfs/releases/download/v${version}/git-lfs-darwin-amd64-v${version}.tar.gz";
    sha256 = "0lg142inj7iqva4cfndvvidi0dmprkglllmj4iidwdzhcavlvbnl";
    # date = 2020-05-16T00:38:51-0800;
  };

  phases = [ "unpackPhase" "installPhase" ];

  unpackPhase = ''
    tar xvzf ${src}
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp -p git-lfs $out/bin
  '';

  meta = with stdenv.lib; {
    description = "An open source Git extension for versioning large files";
    homepage = https://git-lfs.github.com/;
    license = licenses.mit;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.unix;
  };
};

}
