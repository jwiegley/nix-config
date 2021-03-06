self: super: {

git-lfs = with super; stdenv.mkDerivation rec {
  name = "git-lfs-${version}";
  version = "2.13.2";

  src = fetchurl {
    url = "https://github.com/git-lfs/git-lfs/releases/download/v${version}/git-lfs-darwin-amd64-v${version}.zip";
    sha256 = "1jsng8v9xhd9q2sg0h7iy0x7g3hsg99ffsrs0671x0mfvx15vfn2";
    # date = 2020-05-16T00:38:51-0800;
  };

  phases = [ "unpackPhase" "installPhase" ];

  buildInputs = [ unzip ];

  unpackPhase = ''
    unzip ${src}
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp -p git-lfs $out/bin
  '';

  meta = with super.lib; {
    description = "An open source Git extension for versioning large files";
    homepage = https://git-lfs.github.com/;
    license = licenses.mit;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.unix;
  };
};

}
