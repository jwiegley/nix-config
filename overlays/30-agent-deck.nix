# overlays/30-agent-deck.nix
# Purpose: agent-deck - Terminal (tmux) session manager for AI coding agents
# Dependencies: Uses prev only
# Packages: agent-deck
_final: prev: {

  agent-deck =
    with prev;
    buildGoModule rec {
      pname = "agent-deck";
      version = "1.9.73";

      src = fetchFromGitHub {
        owner = "asheshgoplani";
        repo = "agent-deck";
        tag = "v${version}";
        hash = "sha256-4LbeRiaFIn4Nx/VtDvhJAaeA7YB6i2VX8wZhJ75qw5k=";
      };

      vendorHash = "sha256-teB9HxMGOe5YGW0RGxVOhkDPyczCDdjATRV9Mn9ixDU=";

      # 2026-07-15 ares fleet incident: codex refuses user-initiated turns on
      # any thread whose rollout session_meta says thread_source=subagent —
      # resume loads it and goal mode auto-continues, but the first typed
      # message exits the TUI with "Error: turn/start failed in TUI", killing
      # the tmux session in an error loop. agent-deck rebinds
      # tool_data.codex_session_id to a subagent id via three id-rotation
      # paths (the agent-turn-complete notify hook, the live-process FD probe,
      # and the cold-start disk scan), none of which had a quality gate, so a
      # restart then resumed the wrong thread. The patch adds a rebind gate on
      # all three paths (reject subagent-sourced candidates) plus a
      # restart-time safety net (launch subagent-sourced bindings with
      # `codex fork <sid>`, which carries the context into a fresh
      # user-sourced thread). Committed locally as jwiegley/agent-deck
      # 41d42f9e; go.mod untouched, so vendorHash is unaffected. DROP once an
      # upstream release past v1.9.73 ships the fix (PR #1622).
      patches = [ ./patches/agent-deck-codex-subagent-gate.patch ];

      # Only the user-facing TUI/CLI. cmd/agent-deck-test-server is a test helper
      # and is not shipped by upstream (goreleaser builds cmd/agent-deck alone).
      subPackages = [ "cmd/agent-deck" ];

      # Pure Go: SQLite is modernc.org/sqlite, so no cgo is needed. Matches
      # upstream's goreleaser build (CGO_ENABLED=0) and keeps cross-platform
      # builds toolchain-free.
      env.CGO_ENABLED = "0";

      ldflags = [
        "-s"
        "-w"
        "-X"
        "main.Version=${version}"
      ];

      # The web UI's styles.css and every other //go:embed target are committed
      # artifacts, so the build needs no tailwind, npm, or go-generate step.

      # Upstream's test suite needs a real tmux, the race detector, and network
      # access, none of which exist in the Nix sandbox. Smoke-test the built
      # binary instead (mirrors the Homebrew formula's `agent-deck version`).
      doCheck = false;

      nativeBuildInputs = [ makeWrapper ];

      # agent-deck is a tmux session manager: tmux is a hard runtime requirement
      # (the binary exits at startup when it is missing), and git backs the
      # worktree and fork features. Use --suffix so a user's own tmux/git still
      # take precedence: that keeps the tmux client and server on the same binary
      # (a mismatched client/server pair fails with a protocol-version error when
      # the user runs `tmux attach` themselves) and honours this flake's policy of
      # not replacing the user's git. The store copies are only a fallback for a
      # machine that lacks them. Every other integration (jq, jujutsu, docker,
      # the clipboard tools, gh, and the agent CLIs themselves) is probed with
      # exec.LookPath and degrades gracefully, so those are left to the user PATH.
      postInstall = ''
        wrapProgram $out/bin/agent-deck \
          --suffix PATH : ${
            lib.makeBinPath [
              tmux
              git
            ]
          }
      '';

      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck
        $out/bin/agent-deck version | grep -F "${version}"
        runHook postInstallCheck
      '';

      meta = with lib; {
        description = "Terminal session manager for AI coding agents (one tmux TUI for Claude, Codex, Gemini, OpenCode, and more)";
        homepage = "https://github.com/asheshgoplani/agent-deck";
        license = licenses.mit;
        mainProgram = "agent-deck";
        platforms = [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-linux"
        ];
      };
    };

}
