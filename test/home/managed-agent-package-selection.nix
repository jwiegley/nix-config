{
  configured,
  inputs,
  pkgs,
  src,
}:

let
  # External NixOS consumers receive the portable flake as `nix-config-ai`;
  # they do not inherit this repository's flattened `git-ai` input set. Keep
  # this fixture shaped like those consumers so the managed wrappers cannot
  # silently degrade to the upstream packages there.
  downstreamInputs = builtins.removeAttrs inputs [
    "git-ai"
    "nix-ai"
  ];
  packages = import "${src}/config/packages.nix" {
    hostname = "vulcan";
    inputs = downstreamInputs;
    pkgs = configured;
    isClientMachine = false;
  };
  hasManagedClaude = builtins.any (
    package:
    builtins.hasAttr "name" package
    && configured.lib.hasInfix "claude-code" package.name
    && configured.lib.hasSuffix "-managed-config" package.name
  ) packages.package-list;
in
assert configured.lib.assertMsg hasManagedClaude
  "downstream nix-config-ai consumers lost the managed Claude wrapper";
pkgs.runCommand "managed-agent-package-selection" { } "touch $out"
