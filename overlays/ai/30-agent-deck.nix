_final: prev:
let
  source = (import ../../packages/source-catalog.nix "ai").agent-deck;
in
{

  agent-deck =
    with prev;
    # Upstream's module requires Go 1.26.
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
        ./patches/agent-deck-runtime-lifecycle.patch
      ];
      patchFlags = [
        "-p1"
        "--fuzz=0"
      ];

      # Go 1.26's arm64 race runtime only supports a 48-bit VMA. Vulcan's
      # 16 KiB-page kernel exposes a different layout, so race binaries abort
      # before any test executes. Keep the complete lifecycle suite and every
      # fail/skip gate there; the Darwin and x86_64-linux builds retain the
      # race-instrumented lane.
      postPatch = lib.optionalString (stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64) ''
        substituteInPlace Makefile \
          --replace-fail \
            "go test -race -json -count=1 -run '^TestRuntimeLifecycle_'" \
            "go test -json -count=1 -run '^TestRuntimeLifecycle_'"
      '';

      # Only the user-facing TUI/CLI. cmd/agent-deck-test-server is a test helper
      # and is not shipped by upstream (goreleaser builds cmd/agent-deck alone).
      subPackages = [ "cmd/agent-deck" ];

      # The shipped binary remains pure Go. Lifecycle checks use CGO because
      # the Darwin and x86_64-linux lanes run Go's race detector; aarch64-linux
      # keeps the same check environment while omitting only that unsupported
      # instrumentation.
      env.CGO_ENABLED = "0";

      ldflags = [
        "-s"
        "-w"
        "-X"
        "main.Version=${version}"
      ];

      # The web UI's styles.css and every other //go:embed target are committed
      # artifacts, so the build needs no tailwind, npm, or go-generate step.

      # Run the source-owned, deterministic runtime lifecycle gate. It covers
      # the patched SQLite/CAS boundary and fake runtime seams without using the
      # user's tmux socket, database, or network. The installed-binary check
      # below still covers the built artifact.
      doCheck = true;
      # An explicit phase is required. subPackages confines the default check
      # scope to cmd/agent-deck, so doCheck alone would run nothing and pass.
      checkPhase = ''
        runHook preCheck
        # Linux Nix builders report /build as their passwd home. Seeding the
        # test sandbox beneath the default TMPDIR would therefore trip Agent
        # Deck's real-home data-loss guard even though the Nix sandbox cannot
        # reach user state. Keep the hermetic test tree at the conventional
        # sandbox-private /tmp path instead.
        TMPDIR=/tmp CGO_ENABLED=1 make GOTOOLCHAIN=local test-runtime-lifecycle
        go test ./internal/session/ -run '^TestShouldRejectCodexSubagentRebind$'
        runHook postCheck
      '';

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

      passthru.runtimeLifecycleRaceEnabled =
        !(stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64);

      meta = with lib; {
        description = "Terminal session manager for AI coding agents";
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
