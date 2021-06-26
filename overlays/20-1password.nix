self: super: {

OnePassword-op = super.stdenv.mkDerivation rec {
  name = "1Password-op";
  version = "1.10.3";
  src = super.fetchurl {
    url = "https://cache.agilebits.com/dist/1P/op/pkg/v${version}/op_darwin_amd64_v${version}.pkg";
    sha256 = "0d68sgk5cak5zbhwywi02gb1yinnb8q3l0sdsgxbwrxq366ffda9";
  };
  buildInputs = [ self.unzip ];
  unpackPhase = ''
    unzip ${src}
  '';
  buildPhase = "";
  installPhase = ''
    mkdir -p $out/bin
    cp op $out/bin
  '';
};

}
