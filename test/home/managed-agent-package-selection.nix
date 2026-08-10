{
  configured,
  inputs,
  pkgs,
  src,
}:

let
  # External NixOS consumers receive the portable flake as `nix-config-ai` and
  # declare `obr` separately for the root module; they do not inherit this
  # repository's flattened `git-ai` input set. Keep this fixture shaped like
  # those consumers so managed wrappers cannot silently degrade upstream.
  downstreamInputs = builtins.removeAttrs inputs [ "git-ai" ];
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

  # A consumer with agent packages but no portable-flake route must fail
  # loudly at evaluation, never silently install unwrapped upstream agents.
  unpatchable = import "${src}/config/packages.nix" {
    hostname = "vulcan";
    inputs = builtins.removeAttrs inputs [
      "git-ai"
      "nix-config-ai"
    ];
    pkgs = configured;
    isClientMachine = false;
  };
  # `all` (unlike `any`) cannot short-circuit before the agent entries: every
  # regular package satisfies the predicate, so evaluation must reach the
  # first managed-agent element and trip its throw.
  degradesLoudly =
    !(builtins.tryEval (
      builtins.all (package: builtins.hasAttr "name" package) unpatchable.package-list
    )).success;
in
assert configured.lib.assertMsg hasManagedClaude
  "downstream nix-config-ai consumers lost the managed Claude wrapper";
assert configured.lib.assertMsg degradesLoudly
  "config/packages.nix silently degraded managed agent wrappers without inputs.nix-config-ai";
pkgs.runCommand "managed-agent-package-selection" { } "touch $out"
