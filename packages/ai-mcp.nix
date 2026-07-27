# Independent Model Context Protocol packages.
# Dependencies: Uses final for python3Packages; uses prev elsewhere
# Includes MCP servers, Claude Code tools, and agent-http-header-bridge.
{
  final,
  prev,
  palMcpServer ? null,
  mcpRemote ? null,
}:

let
  sources = import ./source-catalog.nix "ai";
in
prev.lib.optionalAttrs (palMcpServer != null) {

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

      src = palMcpServer;

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
// prev.lib.optionalAttrs (mcpRemote != null) {

  agent-http-header-bridge =
    let
      source = mcpRemote;
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

          patches = [ ../overlays/ai/patches/mcp-remote-header-only.patch ];

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
}
// {

  # Rust documentation MCP server
  rustdocs-mcp-server =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "rustdocs-mcp-server";
      version = sources.rustdocs-mcp-server.version;

      src =
        assert sources.rustdocs-mcp-server.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.rustdocs-mcp-server.source.args;

      cargoHash = sources.rustdocs-mcp-server.hashes.cargoHash;

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
    buildNpmPackage (_finalAttrs: {
      pname = "browser-control-mcp";
      version = sources.browser-control-mcp.version;

      src =
        assert sources.browser-control-mcp.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.browser-control-mcp.source.args;

      npmDepsHash = sources.browser-control-mcp.hashes.npmDepsHash;

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
    buildNpmPackage (_finalAttrs: {
      pname = "claude-replay";
      version = sources.claude-replay.version;

      src =
        assert sources.claude-replay.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.claude-replay.source.args;

      npmDepsHash = sources.claude-replay.hashes.npmDepsHash;

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
      version = sources.context-hub.version;

      src =
        assert sources.context-hub.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.context-hub.source.args;

      npmDepsHash = sources.context-hub.hashes.npmDepsHash;

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
    buildNpmPackage (_finalAttrs: {
      pname = "drafts-mcp-server";
      version = sources.drafts-mcp-server.version;

      src =
        assert sources.drafts-mcp-server.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.drafts-mcp-server.source.args;

      npmDepsHash = sources.drafts-mcp-server.hashes.npmDepsHash;

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
