self: super: {

git-lfs = with super; stdenv.mkDerivation rec {
  name = "git-lfs-${version}";
  version = "3.7.0";

  src = fetchurl {
    url = "https://github.com/git-lfs/git-lfs/releases/download/v${version}/git-lfs-darwin-arm64-v${version}.zip";
    sha256 = "sha256-NMqd9wMQYbhHHVMHbLdql0dok3ognD/Ko95icOxkZeo=";
    # date = 2020-05-16T00:38:51-0800;
  };

  phases = [ "unpackPhase" "installPhase" ];

  buildInputs = [ unzip ];

  unpackPhase = ''
    unzip ${src}
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp -p git-lfs-${version}/git-lfs $out/bin
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
