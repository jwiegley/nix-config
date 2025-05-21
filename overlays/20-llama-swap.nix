self: super: {

llama-swap = with super; buildGoModule rec {
  pname = "llama-swap";
  version = "121";
  vendorHash = "sha256-5mmciFAGe8ZEIQvXejhYN+ocJL3wOVwevIieDuokhGU=";

  src = fetchFromGitHub {
    owner = "mostlygeek";
    repo = "llama-swap";
    rev = "v${version}";
    hash = "sha256-vKDrG29E28uCdyrTQgd7Q8I9SPuz4V9mkrA6TMfHefQ=";
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
