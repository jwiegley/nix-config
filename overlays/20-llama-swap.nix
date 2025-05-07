self: super: {

llama-swap = with super; buildGoModule rec {
  pname = "llama-swap";
  version = "110";
  vendorHash = "sha256-ERf6uT7QCTR5LxHnbnko/nuFmVIPAAyd+5dP+SUaffA=";

  src = fetchFromGitHub {
    owner = "mostlygeek";
    repo = "llama-swap";
    rev = "v${version}";
    hash = "sha256-f/YMCbvI4JEVooiJLPJN53TDLL9WkOVQJvpGbMTba5I=";
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
