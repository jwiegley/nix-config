# overlays/30-reasondb.nix
# Purpose: AI-native document database with Hierarchical Reasoning Retrieval
# Dependencies: None (uses only prev)
# Packages: reasondb
_final: prev: {

  reasondb =
    with prev;
    let
      # Pre-fetch Swagger UI for utoipa-swagger-ui build script
      swagger-ui = fetchurl {
        url = "https://github.com/swagger-api/swagger-ui/archive/refs/tags/v5.17.14.zip";
        hash = "sha256-SBJE0IEgl7Efuu73n3HZQrFxYX+cn5UU5jrL4T5xzNw=";
      };
    in
    rustPlatform.buildRustPackage rec {
      pname = "reasondb";
      version = "0.1.2";

      src = fetchFromGitHub {
        owner = "reasondb";
        repo = "reasondb";
        rev = "v${version}";
        hash = "sha256-vRGyc8+AvZVyNhYrv1s82EIWAtAaJgxyskXxak+Vn8I=";
      };

      cargoHash = "sha256-Rgoi6T75/SAp278dGjidoxKJvrVgYdZx0S0bAvt1gF8=";

      nativeBuildInputs = [ pkg-config ];
      buildInputs = [ openssl ];

      # Project's .cargo/config.toml may set RUSTC_WRAPPER=sccache
      RUSTC_WRAPPER = "";

      # Point utoipa-swagger-ui to pre-fetched archive
      SWAGGER_UI_DOWNLOAD_URL = "file://${swagger-ui}";

      # Build CLI and server (skip Tauri desktop app)
      cargoBuildFlags = [
        "--package"
        "reasondb-cli"
        "--package"
        "reasondb-server"
      ];

      doCheck = false;

      meta = {
        description = "AI-native document database with Hierarchical Reasoning Retrieval";
        homepage = "https://github.com/reasondb/reasondb";
        license = with lib.licenses; [
          mit
          asl20
        ];
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

}
