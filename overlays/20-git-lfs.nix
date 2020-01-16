self: super: {

git-lfs = with super; stdenv.mkDerivation rec {
  name = "git-lfs-${version}";
  version = "2.9.2";

  src = fetchurl {
    url = "https://github.com/git-lfs/git-lfs/releases/download/v${version}/git-lfs-darwin-amd64-v${version}.tar.gz";
    sha256 = "1s64pg31biyisyh2zjhd4s34idzjga1j7vfm6gbl29z5z8rwcpn5";
    # date = 2020-01-16T00:38:51-0800;
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
