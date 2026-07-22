# overlays/30-ai-mcp.nix
# Purpose: Model Context Protocol (MCP) servers and Claude Code tools
# Dependencies: Uses final for python3Packages; uses prev elsewhere
# Includes MCP servers, Claude Code tools, and agent-http-header-bridge.
final: prev:

prev.lib.optionalAttrs (prev ? inputs && prev.inputs ? pal-mcp-server) {

  # PAL MCP Server - Provider Abstraction Layer for multi-model AI collaboration
  # NOTE: Using 'final' because python3Packages may be modified by
  # pythonPackagesExtensions in other overlays
  pal-mcp-server =
    with final;
    with final.python3Packages;
    buildPythonApplication {
      pname = "pal-mcp-server";
      version = "1.2.1";
      pyproject = true;

      src = prev.inputs.pal-mcp-server;

      build-system = [
        setuptools
        setuptools-scm
      ];

      dependencies = [
        mcp
        google-genai
        openai
        anthropic
        pydantic
        python-dotenv
      ];

      env.SETUPTOOLS_SCM_PRETEND_VERSION = "1.2.1";

      doCheck = false;

      meta = {
        description = "AI-powered MCP server with multiple model providers";
        homepage = "https://github.com/jwiegley/pal-mcp-server";
        license = lib.licenses.mit;
        mainProgram = "pal-mcp-server";
      };
    };

}
// {

  agent-http-header-bridge =
    let
      source = prev.inputs.mcp-remote;
      sourcePackage = builtins.fromJSON (builtins.readFile "${source}/package.json");
      lockHash = builtins.hashFile "sha256" "${source}/pnpm-lock.yaml";
      pnpm = prev.pnpm_10.override { nodejs-slim = prev.nodejs_22; };
      proxy =
        assert sourcePackage.version == "0.1.38";
        assert lockHash == "598f60becf15b3197fce5c4e38e8158f3db2f774d218a443e50b3b5e2b098542";
        prev.stdenv.mkDerivation (finalAttrs: {
          pname = "agent-http-header-bridge-proxy";
          inherit (sourcePackage) version;
          inherit source;
          src = source;

          patches = [ ../patches/mcp-remote-header-only.patch ];

          nativeBuildInputs = [
            prev.nodejs_22
            pnpm
            prev.pnpmConfigHook
          ];

          pnpmDeps = prev.fetchPnpmDeps {
            inherit (finalAttrs) pname version src;
            inherit pnpm;
            fetcherVersion = 3;
            hash = "sha256-8aV/WRBrcezMb8HyRKW89v11MumgQnQwSBde5MZkzos=";
          };

          buildPhase = ''
            runHook preBuild
            pnpm run check
            pnpm run test:unit
            pnpm run build
            pnpm prune --prod --ignore-scripts
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            bridge_lib="$out/libexec/agent-http-header-bridge"
            install -d "$bridge_lib"
            install -m0755 dist/proxy.js "$bridge_lib/proxy.js"
            install -m0644 dist/chunk-*.js "$bridge_lib/"
            install -m0644 package.json "$bridge_lib/package.json"
            cp -R node_modules "$bridge_lib/node_modules"
            install -Dm0644 LICENSE \
              "$out/share/licenses/agent-http-header-bridge/LICENSE"
            runHook postInstall
          '';
        });
    in
    prev.writeShellApplication {
      name = "agent-http-header-bridge";
      passthru = {
        inherit lockHash proxy source;
        inherit (source) narHash rev;
      };
      text = ''
        fail_invalid() {
          printf '%s\n' 'agent-http-header-bridge: invalid invocation' >&2
          exit 2
        }

        fail_credential() {
          printf '%s\n' 'agent-http-header-bridge: credential unavailable' >&2
          exit 2
        }

        [ "$#" -eq 3 ] || fail_invalid
        bridge_url=$1
        bridge_header=$2
        bridge_environment=$3

        [[ "$bridge_url" =~ ^https://[^[:space:]]+$ ]] || fail_invalid
        bridge_header_pattern="^[!#$%&'*+.^_\`|~0-9A-Za-z-]+$"
        [[ "$bridge_header" =~ $bridge_header_pattern ]] || fail_invalid
        [[ "$bridge_environment" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fail_invalid
        if [[ ! -v $bridge_environment ]] || [ -z "''${!bridge_environment}" ]; then
          fail_credential
        fi

        bridge_placeholder='$'"{$bridge_environment}"
        exec -a agent-http-header-bridge ${prev.nodejs_22}/bin/node \
          ${proxy}/libexec/agent-http-header-bridge/proxy.js \
          "$bridge_url" --header "$bridge_header: $bridge_placeholder" \
          --header-only --transport http-only --silent
      '';
      meta = {
        description = "Credential-safe static-header bridge for Droid MCP servers";
        homepage = "https://github.com/geelen/mcp-remote";
        license = prev.lib.licenses.mit;
        mainProgram = "agent-http-header-bridge";
        platforms = prev.lib.platforms.all;
      };
    };

  # Fix: npm prune removes @types/node, then prepare script tries to rebuild
  mcp-server-sequential-thinking = prev.mcp-server-sequential-thinking.overrideAttrs (_old: {
    dontNpmPrune = true;
  });

  # Rust documentation MCP server
  rustdocs-mcp-server =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "rustdocs-mcp-server";
      version = "1.3.1";

      src = fetchFromGitHub {
        owner = "Govcraft";
        repo = "rust-docs-mcp-server";
        rev = "v${version}";
        hash = "sha256-jSa4qKZEtZZvYfoRReGDDqH039RH/7Dimo3jmcnnwak=";
      };

      cargoHash = "sha256-iw7dRzwH42HBj2r9y5IHHKLmER7QkyFzLjh7Q+dNMao=";

      nativeBuildInputs = [
        pkg-config
        perl
        openssl.dev
      ];

      meta = with lib; {
        description = ''
          Fetches the documentation for a specified Rust crate, generates
          embeddings for the content, and provides an MCP tool to answer questions
          about the crate based on the documentation context.
        '';
        homepage = "https://github.com/Govcraft/rust-docs-mcp-server";
        license = licenses.mit;
        mainProgram = "rustdocs_mcp_server";
      };
    };

  # Browser control MCP server
  browser-control-mcp =
    with prev;
    buildNpmPackage (finalAttrs: {
      pname = "browser-control-mcp";
      version = "1.5.1";

      src = fetchFromGitHub {
        owner = "eyalzh";
        repo = "browser-control-mcp";
        tag = "v${finalAttrs.version}";
        hash = "sha256-P0ZYjaHArngobtOf4C3j3LpuwfT4vZdJnoZnzeNoIWo=";
      };

      npmDepsHash = "sha256-NT0r3WHqg6ENVO4aPldUgs2doDJD+EEJcp78nNfbBnQ=";

      makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

      passthru.updateScript = nix-update-script { };

      doInstallCheck = true;
      versionCheckProgram = "${placeholder "out"}/bin/browser-control-mcp";
      versionCheckProgramArg = "--version";

      meta = with lib; {
        description = "MCP server paired with a browser extension that enables AI agents to control the user's browser.";
        homepage = "https://github.com/eyalzh/browser-control-mcp";
        license = licenses.mit;
        mainProgram = "browser-control-mcp";
        platforms = platforms.all;
      };
    });

  # claude-replay - Convert Claude Code transcripts to HTML replays
  claude-replay =
    with prev;
    buildNpmPackage (finalAttrs: {
      pname = "claude-replay";
      version = "0.9.0";

      src = fetchFromGitHub {
        owner = "es617";
        repo = "claude-replay";
        tag = "v${finalAttrs.version}";
        hash = "sha256-aOH/dH1HByuTLzBSZO2WLsMmTU2wDijbWEXAKnsoiD8=";
      };

      npmDepsHash = "sha256-d3OdO3rotMeKmCb5N+V9bWdlGPeQ9cQ9NaNBrptFJL4=";

      makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

      meta = with lib; {
        description = "Convert Claude Code session transcripts into interactive, shareable HTML replays";
        homepage = "https://github.com/es617/claude-replay";
        license = licenses.mit;
        mainProgram = "claude-replay";
        platforms = platforms.all;
      };
    });

  # Context Hub - AI agent documentation CLI and MCP server
  context-hub =
    with prev;
    buildNpmPackage (_finalAttrs: {
      pname = "context-hub";
      version = "67dcbeb2";

      src = fetchFromGitHub {
        owner = "andrewyng";
        repo = "context-hub";
        rev = "67dcbeb2eb42c808549f08397920ad58be7c2206";
        hash = "sha256-iUibrCUVgO3U41x6NEchJRsST++PE92Hz3J0gbGt7p0=";
      };

      npmDepsHash = "sha256-AIjQTnfeXt8ROhHcS2vuYQ2HbXdI/MFa4/wnuQknjKA=";

      npmWorkspace = "cli";

      dontNpmBuild = true;

      npmFlags = [ "--ignore-scripts" ];

      # Remove dangling workspace symlinks left by npm workspace install
      postInstall = ''
        find $out -xtype l -delete
      '';

      makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

      meta = with lib; {
        description = "CLI and MCP server for Context Hub - search and retrieve LLM-optimized docs for AI agents";
        homepage = "https://github.com/andrewyng/context-hub";
        license = licenses.mit;
        mainProgram = "chub";
        platforms = platforms.all;
      };
    });

  # drafts-mcp-server - MCP server that drives the Drafts app on macOS via
  # AppleScript (osascript). macOS-only by design (the upstream package.json
  # declares `"os": ["darwin"]`): it cannot run on Linux, so meta.platforms is
  # darwin and config/packages.nix installs it only under `isDarwin`. The
  # TypeScript source is compiled to dist/ by `tsc` (npm run build).
  drafts-mcp-server =
    with prev;
    buildNpmPackage (finalAttrs: {
      pname = "drafts-mcp-server";
      version = "1.0.12";

      src = fetchFromGitHub {
        owner = "agiletortoise";
        repo = "drafts-mcp-server";
        tag = "v${finalAttrs.version}";
        hash = "sha256-SZp//UKyFfwJyu7Cn5pG3Rp7P9l+4ElDZO7vYp78WzY=";
      };

      npmDepsHash = "sha256-nypoTffI8WIF9Et2GWLe/3odNJka9MSYuaP7xtLIoyg=";

      makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

      meta = with lib; {
        description = "MCP server that lets AI assistants drive the Drafts app on macOS via AppleScript";
        homepage = "https://github.com/agiletortoise/drafts-mcp-server";
        license = licenses.mit;
        mainProgram = "drafts-mcp-server";
        platforms = platforms.darwin;
      };
    });

}
