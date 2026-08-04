let
  gallery = import ../../packages/pi-gallery/manifest.nix {
    inputs.ponytail.rev = "0000000";
    packages = { };
  };
  galleryPackages =
    map (id: gallery.members.${id}.attrName) gallery.order
    ++ map (source: source.attrName) (builtins.attrValues gallery.supportSources);
  portableLock = builtins.fromJSON (builtins.readFile ../../config/fleet/flake.lock);
in
{
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

  inputs = builtins.attrNames portableLock.nodes.root.inputs;

  topLevel = [
    [
      "overlays"
      "default"
    ]
    [
      "overlays"
      "tools"
    ]
    [
      "lib"
      "aiPackagesFor"
    ]
    [
      "lib"
      "patchAgentPackage"
    ]
  ];

  packages = builtins.sort builtins.lessThan (
    [
      "agent-http-header-bridge"
      "agent-resources"
      "default"
      "nix-scripts"
      "pi"
      "pi-gallery"
      "plasma-fractal"
      "plasma-wiki"
    ]
    ++ galleryPackages
  );

  # Truthful evidence-bearing app names plus the conventional `default` alias.
  # `no-warnings` is a real app running no-warnings.sh.
  apps = [
    "build-check"
    "check"
    "default"
    "format"
    "format-check"
    "lint"
    "no-warnings"
    "test"
  ];

  # `compatibility-contract` is grafted onto the checked output after this list
  # is compared with the portable definition, so it is deliberately absent.
  # Retired check aliases produced no independent evidence; the real apps and
  # behavioral checks remain.
  checks = [
    "agent-deck-go-compat"
    "agent-resources"
    "agent-wrappers"
    "build"
    "format"
    "fractal-smoke"
    "input-projection-parity"
    "lint"
    "llama-cpp-platform-compat"
    "llm-agents-nixpkgs-independent"
    "pi-fleet-theme"
    "pi-gallery"
  ];
}
