# overlays/30-ai-mcp.nix
# Purpose: Model Context Protocol (MCP) servers and Claude Code tools
# Dependencies: Uses final for python3Packages and claude-code-acp; uses prev elsewhere
# Packages: pal-mcp-server, mcp-server-sequential-thinking, rustdocs-mcp-server,
#           browser-control-mcp, claude-code-acp, context-hub
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
      version = "9.8.2";
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
        pydantic
        python-dotenv
      ];

      env.SETUPTOOLS_SCM_PRETEND_VERSION = "9.8.2";

      doCheck = false;

      meta = {
        description = "AI-powered MCP server with multiple model providers";
        homepage = "https://github.com/BeehiveInnovations/pal-mcp-server";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
        mainProgram = "pal-mcp-server";
      };
    };

}
// {

  # Fix: npm prune removes @types/node, then prepare script tries to rebuild
  mcp-server-sequential-thinking = prev.mcp-server-sequential-thinking.overrideAttrs (old: {
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
        maintainers = with maintainers; [ jwiegley ];
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
        maintainers = [ maintainers.jwiegley ];
        platforms = platforms.all;
      };
    });

  # claude-replay - Convert Claude Code transcripts to HTML replays
  claude-replay =
    with prev;
    buildNpmPackage (finalAttrs: {
      pname = "claude-replay";
      version = "0.5.3";

      src = fetchFromGitHub {
        owner = "es617";
        repo = "claude-replay";
        tag = "v${finalAttrs.version}";
        hash = "sha256-WlX0djAU8WXg2x/HILc4l6OouPM8e5xLEmjN0mfqHjE=";
      };

      npmDepsHash = "sha256-ikleWdiFxdJLuwICbwuardAmjWzh21fAaPBgyd9ER24=";

      makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

      meta = with lib; {
        description = "Convert Claude Code session transcripts into interactive, shareable HTML replays";
        homepage = "https://github.com/es617/claude-replay";
        license = licenses.mit;
        mainProgram = "claude-replay";
        maintainers = [ maintainers.jwiegley ];
        platforms = platforms.all;
      };
    });

  # Context Hub - AI agent documentation CLI and MCP server
  context-hub =
    with prev;
    buildNpmPackage (finalAttrs: {
      pname = "context-hub";
      version = "8cf23490";

      src = fetchFromGitHub {
        owner = "andrewyng";
        repo = "context-hub";
        rev = "8cf23490c9fff3ca9b23e477aa81092a2469f5d6";
        hash = "sha256-9gTImdGZYM+ecqEyOXPiDxu8zHR8nPbdiYyEUmiFkbo=";
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
        maintainers = [ maintainers.jwiegley ];
        platforms = platforms.all;
      };
    });

  # Claude Code ACP - Use Claude Code from ACP-compatible clients
  # NOTE: Using 'final' here because claude-code-acp may need packages
  # defined earlier in this overlay
  claude-code-acp =
    with final;
    buildNpmPackage (finalAttrs: {
      pname = "claude-code-acp";
      version = "0.22.2";

      src = fetchFromGitHub {
        owner = "zed-industries";
        repo = "claude-code-acp";
        rev = "v${finalAttrs.version}";
        hash = "sha256-JkSE6fwtM1btfuxbwX7b04cbTDr5SdYEb7qwlZK9JYo=";
      };

      npmDepsHash = "sha256-9OhdDRQuekmt3JMs0oGVbvqWcQFoyk4ZZlm6DZCNazU=";

      dontNpmBuild = false;

      npmFlags = [ "--ignore-scripts" ];

      makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

      passthru.updateScript = nix-update-script { };

      # Version check disabled - command doesn't support --version flag
      doInstallCheck = false;

      meta = with lib; {
        description = "Use Claude Code from any ACP-compatible clients such as Zed";
        homepage = "https://github.com/zed-industries/claude-code-acp";
        license = licenses.asl20;
        mainProgram = "claude-code-acp";
        maintainers = [ maintainers.jwiegley ];
        platforms = platforms.all;
      };
    });

}
