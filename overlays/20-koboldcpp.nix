self: super: {

koboldcpp = super.koboldcpp.overrideAttrs(attrs: rec {
  version = "1.91";
    
  src = super.fetchFromGitHub {
    owner = "LostRuins";
    repo = "koboldcpp";
    tag = "v${version}";
    hash = "sha256-s2AfdKF4kUez3F1P+FYMbP2KD+J6+der/datxrdTiZU=";
  };
});

}
