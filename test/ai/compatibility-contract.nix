let
  gallery = import ../../packages/pi-gallery/manifest.nix {
    inputs.ponytail.rev = "0000000";
    packages = { };
  };
  galleryPackages =
    map (id: gallery.members.${id}.attrName) gallery.order
    ++ map (source: source.attrName) (builtins.attrValues gallery.supportSources);
  portableLock = builtins.fromJSON (builtins.readFile ../../config/ai/flake.lock);
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

  apps = [
    "build-check"
    "check"
    "coverage"
    "coverage-check"
    "default"
    "format"
    "format-check"
    "fuzz"
    "lint"
    "memory-check"
    "no-warnings"
    "profile"
    "profile-check"
    "test"
  ];

  checks = [
    "agent-deck-go-compat"
    "agent-resources"
    "agent-wrappers"
    "build"
    "coverage"
    "format"
    "fractal-smoke"
    "fuzz"
    "lint"
    "llama-cpp-platform-compat"
    "llm-agents-nixpkgs-independent"
    "memory"
    "no-warnings"
    "pi-gallery"
    "profile"
    "tests"
  ];
}
