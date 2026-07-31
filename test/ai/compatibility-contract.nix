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
      "pi-gallery"
      "plasma-fractal"
      "plasma-wiki"
    ]
    ++ galleryPackages
  );

  # Only names whose output executes what the name says. `no-warnings` stays: it
  # is a real app running no-warnings.sh, not an alias. See #48.
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

  # `compatibility-contract` is deliberately absent: this list is compared against
  # the flake DEFINITION (flake.nix:150 passes actual = portableAiDefinition),
  # before that check is grafted on, so including it would never match.
  #
  # The five removed entries (coverage, fuzz, memory, no-warnings, profile) were
  # aliases of tests/lint/build that produced no evidence of their own. Genuine
  # no-warnings evidence survives as the app. See #48.
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
    "pi-gallery"
    "tests"
  ];
}
