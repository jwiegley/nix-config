self: super: {

OnePassword-op = super.stdenv.mkDerivation rec {
  name = "1Password-op";
  version = "0.6.2";
  src = super.fetchurl {
    url = "https://cache.agilebits.com/dist/1P/op/pkg/v${version}/op_darwin_amd64_v${version}.zip";
    sha256 = "021pmjg1qadyby1afihpj0q7r69ppn29l6zriq7ba5qlzwgcwfgl";
    # date = 2019-10-04T11:16:19-0700;
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
