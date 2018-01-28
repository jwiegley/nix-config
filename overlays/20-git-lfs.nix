self: super: {

git-lfs = with super; stdenv.mkDerivation rec {
  name = "git-lfs-${version}";
  version = "2.3.4";

  src = fetchurl {
    url = https://github.com/git-lfs/git-lfs/releases/download/v2.3.4/git-lfs-darwin-amd64-2.3.4.tar.gz;
    sha256 = "1nvfaxrvrc0qbx78ar1jj3bvh9f4gjvv3vbvwbh39ymid5s4nvdi";
    # date = 2018-01-28T00:38:51-0800;
  };

  phases = [ "unpackPhase" "installPhase" ];

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
