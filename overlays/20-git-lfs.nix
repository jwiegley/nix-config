self: super: {

git-lfs = with super; stdenv.mkDerivation rec {
  name = "git-lfs-${version}";
  version = "2.6.1";

  src = fetchurl {
    url = "https://github.com/git-lfs/git-lfs/releases/download/v${version}/git-lfs-darwin-amd64-v${version}.tar.gz";
    sha256 = "12rcqc0z6awsf1nsili5f0jhpkxig1vmng8wzmzgifjvqm9lkb44";
    # date = 2018-12-27T00:38:51-0800;
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
