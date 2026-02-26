# overlays/30-opencode-tps.nix
# Purpose: Patch opencode with tokens-per-second display (PR #12721)
# Dependencies: None (pre-built binary, uses only prev)
# Packages: opencode_patched
#
# Upstream PR: https://github.com/anomalyco/opencode/pull/12721
# Built from: JohnC0de/opencode feat/tokens-per-second-display (commit 4687e48e9)
# Binary at:  ~/.local/share/opencode-patched/opencode (standalone Bun executable)
#
# Remove this overlay once the TPS feature is merged into a release.
final: prev: {

  opencode_patched =
    let
      version = "0.0.0-tps+20260226";

      # Pre-built binary from the PR branch, fetched at build time via
      # fixed-output derivation to avoid impure eval with absolute paths.
      src = prev.fetchurl {
        url = "file:///Users/johnw/.local/share/opencode-patched/opencode";
        hash = "sha256-K/qAg5X6a5bB6cNofkxc7NVtSM2sMiQBqSTT2wWkKnc=";
        executable = true;
      };
    in
    with prev;
    stdenv.mkDerivation {
      pname = "opencode-patched";
      inherit version;

      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;
      dontStrip = true; # standalone Bun executable; stripping breaks it

      nativeBuildInputs = [ makeBinaryWrapper ];

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        install -m755 ${src} $out/bin/opencode
        wrapProgram $out/bin/opencode \
          --prefix PATH : ${lib.makeBinPath [ fzf ripgrep ]}
        runHook postInstall
      '';

      meta = {
        description = "AI coding agent for the terminal (patched with TPS display, PR #12721)";
        homepage = "https://github.com/anomalyco/opencode";
        license = lib.licenses.mit;
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        platforms = [ "aarch64-darwin" ];
        mainProgram = "opencode";
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

}
