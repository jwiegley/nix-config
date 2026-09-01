# overlays/30-recordings.nix
# Purpose: Voice-recording transcription daemon (Haskell)
# Dependencies: final.haskellPackages
# Packages: recordings
# Notes:
#   - built with callCabal2nix against this nixpkgs (its own flake uses
#     haskell.nix for development only); the sydtest suite runs in checks
{
  recordings ? null,
}:
final: prev:

prev.lib.optionalAttrs (recordings != null) {
  recordings = final.haskellPackages.callCabal2nix "recordings" recordings { };
}
