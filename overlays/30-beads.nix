# overlays/30-beads.nix
# Purpose: Pin beads (bd) to a newer version than nixpkgs
# Dependencies: None (uses only prev)
# Packages: beads
final: prev: {

  beads =
    (prev.beads.override {
      buildGoModule = prev.buildGoModule.override { go = prev.go_1_26; };
    }).overrideAttrs
      (old: rec {
        version = "0.52.0";

        src = prev.fetchFromGitHub {
          owner = "steveyegge";
          repo = "beads";
          tag = "v${version}";
          hash = "sha256-y0DBCmcHUK96VJkOI1WaenEnALUK9J4L4aTzJEfn73Y=";
        };

        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.pkg-config ];
        buildInputs = (old.buildInputs or [ ]) ++ [ prev.icu ];

        ldflags = (old.ldflags or [ ]) ++ [
          "-X main.Version=${version}"
        ];

        # Tests require daemon socket binding which fails in the Nix sandbox
        doCheck = false;

        vendorHash = "sha256-s9ELOxDHHk+RyImrPxm9DPos7Wb4AFWaNKsrgU4soow=";
      });

}
