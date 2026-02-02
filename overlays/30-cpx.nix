# overlays/30-cpx.nix
# Purpose: cpx - Modern, fast file copy tool with progress bars and resume support
# Dependencies: Rust, Linux-specific (copy_file_range syscall)
# Packages: cpx
final: prev: {

  cpx = with prev;
    rustPlatform.buildRustPackage rec {
      pname = "cpx";
      version = "0.1.3";

      src = fetchFromGitHub {
        owner = "11happy";
        repo = "cpx";
        tag = "v${version}";
        hash = "sha256-tZ9NQUwnbONpJ59ByvgHESqqBWz6RaPgY6842VuAlL0=";
      };

      cargoHash = "sha256-atEB43eB8btQfMXPTCfsZ6bbAUIPzF8lUELx0Rdul84=";

      # cpx is currently Linux-only (uses copy_file_range syscall)
      # Skip build on Darwin
      meta = with lib; {
        description =
          "A modern, fast file copy tool for Linux with progress bars, resume capability, and more";
        homepage = "https://github.com/11happy/cpx";
        license = licenses.mit;
        maintainers = with maintainers; [ jwiegley ];
        platforms = platforms.linux;
        mainProgram = "cpx";
      };
    };

}
