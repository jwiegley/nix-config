self: super: {

  nix222 = super.nixStable.overrideAttrs (attrs: rec {
    name = "nix-2.2.2";
    src = self.fetchurl {
      url = "http://nixos.org/releases/nix/${name}/${name}.tar.xz";
      sha256 = "0k2rm3naj5wj7v7yq0s3zxcm8crqa2fpddzh14rd7a1pk17in2pq";
    };
  });

}
