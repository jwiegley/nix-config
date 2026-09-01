# overlays/30-recordings.nix
# Purpose: Voice-recording transcription daemon (Rust)
# Dependencies: final.rustPlatform
# Packages: recordings
# Notes:
#   - built from Cargo.lock against this nixpkgs; tests run during the build
{
  recordings ? null,
}:
final: prev:

prev.lib.optionalAttrs (recordings != null) {
  recordings = final.rustPlatform.buildRustPackage {
    pname = "recordings";
    version = "1.0.0";
    src = recordings;
    cargoLock.lockFile = recordings + "/Cargo.lock";
    strictDeps = true;
    meta = {
      description = "Watch, transcribe, clean, and archive voice recordings";
      license = final.lib.licenses.bsd3;
      mainProgram = "recordings";
    };
  };
}
