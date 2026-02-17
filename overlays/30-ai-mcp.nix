# overlays/30-ai-mcp.nix
# Purpose: Model Context Protocol (MCP) servers and Claude Code tools
# Dependencies: Uses final for claude-code-acp; uses prev elsewhere
# Packages: mcp-server-sequential-thinking, rustdocs-mcp-server,
#           browser-control-mcp, claude-code-acp, ralph-claude-code
final: prev: {

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

  # Claude Code ACP - Use Claude Code from ACP-compatible clients
  # NOTE: Using 'final' here because claude-code-acp may need packages
  # defined earlier in this overlay
  claude-code-acp =
    with final;
    buildNpmPackage (finalAttrs: {
      pname = "claude-code-acp";
      version = "0.16.1";

      src = fetchFromGitHub {
        owner = "zed-industries";
        repo = "claude-code-acp";
        rev = "v${finalAttrs.version}";
        hash = "sha256-/HeAz0jdXhLhYGcwTgthrE7cGjKjro30GQUmAn4egXs=";
      };

      npmDepsHash = "sha256-poTtwIIPHcgQ2uyIUIWVOpHbdDIzVgympa7aHtuSMok=";

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

  # Ralph for Claude Code - Autonomous AI development loop
  ralph-claude-code =
    with prev;
    stdenv.mkDerivation rec {
      pname = "ralph-claude-code";
      version = "b77cc991";

      src = fetchFromGitHub {
        owner = "frankbria";
        repo = "ralph-claude-code";
        rev = "b77cc991dc38e4be5eba4a722583572d5aee9644";
        sha256 = "sha256-MuGcWOufqvBCxdpWVLBqMLrMNoe7jJv62ZWW7C5uxZw=";
        # date = 2026-02-16;
      };

      nativeBuildInputs = [ makeWrapper ];

      buildInputs = [
        bash
        jq
        git
        coreutils
        tmux
      ];

      installPhase = ''
        mkdir -p $out/share/ralph-claude-code
        mkdir -p $out/bin

        # Install main scripts
        cp -p ralph_loop.sh $out/share/ralph-claude-code/
        cp -p setup.sh $out/share/ralph-claude-code/
        cp -p ralph_monitor.sh $out/share/ralph-claude-code/
        cp -p ralph_import.sh $out/share/ralph-claude-code/
        cp -p ralph_enable.sh $out/share/ralph-claude-code/
        cp -p ralph_enable_ci.sh $out/share/ralph-claude-code/
        cp -p migrate_to_ralph_folder.sh $out/share/ralph-claude-code/

        # Install library scripts
        cp -rp lib $out/share/ralph-claude-code/

        # Install templates if they exist
        if [ -d templates ]; then
          cp -rp templates $out/share/ralph-claude-code/
        fi

        # Create wrapper for ralph (main command)
        makeWrapper $out/share/ralph-claude-code/ralph_loop.sh $out/bin/ralph \
          --prefix PATH : ${lib.makeBinPath [ bash jq git coreutils tmux ]} \
          --set RALPH_HOME $out/share/ralph-claude-code

        # Create wrapper for ralph-monitor
        makeWrapper $out/share/ralph-claude-code/ralph_monitor.sh $out/bin/ralph-monitor \
          --prefix PATH : ${lib.makeBinPath [ bash jq git coreutils tmux ]} \
          --set RALPH_HOME $out/share/ralph-claude-code

        # Create wrapper for ralph-setup
        makeWrapper $out/share/ralph-claude-code/setup.sh $out/bin/ralph-setup \
          --prefix PATH : ${lib.makeBinPath [ bash jq git coreutils tmux ]} \
          --set RALPH_HOME $out/share/ralph-claude-code

        # Create wrapper for ralph-import
        makeWrapper $out/share/ralph-claude-code/ralph_import.sh $out/bin/ralph-import \
          --prefix PATH : ${lib.makeBinPath [ bash jq git coreutils tmux ]} \
          --set RALPH_HOME $out/share/ralph-claude-code

        # Create wrapper for ralph-enable
        makeWrapper $out/share/ralph-claude-code/ralph_enable.sh $out/bin/ralph-enable \
          --prefix PATH : ${lib.makeBinPath [ bash jq git coreutils tmux ]} \
          --set RALPH_HOME $out/share/ralph-claude-code

        # Create wrapper for ralph-enable-ci
        makeWrapper $out/share/ralph-claude-code/ralph_enable_ci.sh $out/bin/ralph-enable-ci \
          --prefix PATH : ${lib.makeBinPath [ bash jq git coreutils tmux ]} \
          --set RALPH_HOME $out/share/ralph-claude-code

        # Create wrapper for ralph-migrate
        makeWrapper $out/share/ralph-claude-code/migrate_to_ralph_folder.sh $out/bin/ralph-migrate \
          --prefix PATH : ${lib.makeBinPath [ bash jq git coreutils tmux ]} \
          --set RALPH_HOME $out/share/ralph-claude-code
      '';

      meta = with lib; {
        description = "Autonomous AI development loop for Claude Code with intelligent exit detection";
        homepage = "https://github.com/frankbria/ralph-claude-code";
        license = licenses.mit;
        mainProgram = "ralph";
        maintainers = [ maintainers.jwiegley ];
        platforms = platforms.unix;
      };
    };

}
