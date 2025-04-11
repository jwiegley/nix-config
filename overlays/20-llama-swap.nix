self: super: {

llama-swap = with super; buildGoModule rec {
  pname = "llama-swap";
  version = "103";
  vendorHash = "sha256-7uvkUbj5s/gmX1m6sIuuFl+TGF74qk64O3j9/pFbc+Q=";

  src = fetchFromGitHub {
    owner = "mostlygeek";
    repo = "llama-swap";
    rev = "v${version}";
    hash = "sha256-uLUORiAx/kUUP+WOvq5LImmXjlReM3cG3MSXHj8/fZw=";
  };

  doCheck = false;

  meta = with lib; {
    description = "llama-swap is a light weight, transparent proxy server that provides automatic model swapping to llama.cpp's server";
    homepage = "https://github.com/mostlygeek/llama-swap";
    license = licenses.mit;
    maintainers = [ maintainers.jwiegley ];
  };
};

}
