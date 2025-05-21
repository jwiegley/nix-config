self: super: {

llama-cpp = super.llama-cpp.overrideAttrs(attrs: rec {
  version = "5437";
    
  src = super.fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    tag = "b${version}";
    hash = "sha256-Y8/S0kuc1ARIdc5klWQkzLVJUpW1Nb/plmSLPyCQdvQ=";
  };
});

}
