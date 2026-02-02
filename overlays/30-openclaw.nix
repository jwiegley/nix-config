# overlays/30-openclaw.nix
# Purpose: OpenClaw - Local AI assistant that executes tasks
# Dependencies: Node.js >=22.12.0, native modules (vips, sqlite)
# Packages: openclaw
final: prev: {

  openclaw = with prev;
    stdenv.mkDerivation rec {
      pname = "openclaw";
      version = "2026.2.1";

      src = fetchFromGitHub {
        owner = "openclaw";
        repo = "openclaw";
        tag = "v${version}";
        hash = "sha256-oT2dZj5kB5xv6dJeh5nchnVHblfcpC31LzsoL4ON1qw=";
      };

      pnpmDeps = fetchPnpmDeps {
        inherit pname version src;
        fetcherVersion = 3;
        hash = "sha256-NxKHy1q7A1zWrwZZGv7Yq5tr3ZyKJYDcKbUV6mSt70Y=";
      };

      nativeBuildInputs =
        [ nodejs_22 pnpmConfigHook pnpm pkg-config python3 makeWrapper ];

      buildInputs = [
        nodejs_22
        vips # For sharp (image processing)
        sqlite # For better-sqlite3
      ];

      # Environment variables to control build behavior
      env = {
        # Prevent Playwright from downloading browsers during build
        PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";

        # Force Sharp to build from source using Nix-provided libvips
        npm_config_build_from_source = "true";
        SHARP_IGNORE_GLOBAL_LIBVIPS = "0";
      };

      buildPhase = ''
        runHook preBuild

        # Run the build script
        pnpm build

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        # Clean and reinstall production dependencies only
        rm -rf node_modules
        pnpm install --force --offline --production --ignore-scripts

        # Create output directories
        mkdir -p $out/lib/openclaw
        mkdir -p $out/bin

        # Copy the built application and all workspace packages
        cp -r dist $out/lib/openclaw/
        cp -r node_modules $out/lib/openclaw/
        cp package.json $out/lib/openclaw/
        cp -r scripts $out/lib/openclaw/

        # Copy pnpm workspace packages (monorepo structure)
        cp -r extensions $out/lib/openclaw/ || true
        cp -r packages $out/lib/openclaw/ || true
        cp -r ui $out/lib/openclaw/ || true

        # Remove dev dependency node_modules from workspace packages to avoid broken symlinks
        rm -rf $out/lib/openclaw/ui/node_modules || true
        find $out/lib/openclaw/packages -name node_modules -type d -exec rm -rf {} + || true
        find $out/lib/openclaw/extensions -name node_modules -type d -exec rm -rf {} + || true

        # Create wrapper script
        makeWrapper ${nodejs_22}/bin/node $out/bin/openclaw \
          --add-flags "$out/lib/openclaw/dist/entry.js" \
          --set NODE_PATH "$out/lib/openclaw/node_modules" \
          --prefix PATH : ${lib.makeBinPath [ nodejs_22 ]} \
          --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD "1"

        runHook postInstall
      '';

      # Skip tests that require network or browsers
      doCheck = false;

      meta = with lib; {
        description = "Your own personal AI assistant - runs locally on any OS";
        homepage = "https://github.com/openclaw/openclaw";
        license = licenses.mit;
        maintainers = with maintainers; [ jwiegley ];
        platforms = platforms.darwin ++ platforms.linux;
        mainProgram = "openclaw";
      };
    };

}
