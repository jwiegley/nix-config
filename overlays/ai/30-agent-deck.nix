# Purpose: agent-deck - Terminal (tmux) session manager for AI coding agents
# Dependencies: Uses prev only; Go 1.26 satisfies the upstream module floor
# Packages: agent-deck
_final: prev:
let
  source = (import ../../packages/source-catalog.nix "ai").agent-deck;
in
{

  agent-deck =
    with prev;
    buildGo126Module rec {
      pname = "agent-deck";
      inherit (source) version;

      src =
        assert source.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub source.source.args;

      vendorHash = source.hashes.vendorHash;

      patches = [
        ./patches/agent-deck-discord-typing-best-effort.patch
        ./patches/agent-deck-transition-daemon-churn.patch
        ./patches/agent-deck-last-started-compat.patch
      ];

      # Only the user-facing TUI/CLI. cmd/agent-deck-test-server is a test helper
      # and is not shipped by upstream (goreleaser builds cmd/agent-deck alone).
      subPackages = [ "cmd/agent-deck" ];

      # SQLite is pure Go, so CGO stays disabled and no C toolchain is required.
      env.CGO_ENABLED = "0";

      ldflags = [
        "-s"
        "-w"
        "-X"
        "main.Version=${version}"
      ];

      # The web UI's styles.css and every other //go:embed target are committed
      # artifacts, so the build needs no tailwind, npm, or go-generate step.

      # Use the installed-binary check below instead of the upstream test suite.
      doCheck = false;

      nativeBuildInputs = [ makeWrapper ];

      # Keep user-selected tmux and Git first on PATH; store copies are fallbacks.
      postInstall = ''
        wrapProgram $out/bin/agent-deck \
          --set-default TMUX_TMPDIR /tmp \
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
