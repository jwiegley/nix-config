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
  downstreamInputs = (builtins.removeAttrs inputs [ "git-ai" ]) // {
    nixpkgs = inputs.nixpkgs // {
      legacyPackages = throw "config/packages.nix reopened the stock nixpkgs package set";
    };
  };
  packages = import "${src}/config/packages.nix" {
    hostname = "vulcan";
    inputs = downstreamInputs;
    pkgs = configured;
    isClientMachine = false;
  };
  canonicalCodex = inputs.nix-config-ai.packages.${pkgs.stdenv.hostPlatform.system}.codex;
  hasCanonicalCodex = builtins.any (
    package: package.drvPath == canonicalCodex.drvPath
  ) packages.package-list;
  hasManagedClaude = builtins.any (
    package:
    builtins.hasAttr "name" package
    && configured.lib.hasInfix "claude-code" package.name
    && configured.lib.hasSuffix "-managed-config" package.name
  ) packages.package-list;
  # Force every conditional list spine, but no package derivation, so either
  # predicate reopening the poisoned stock package set fails here.
  avoidsLegacyPackages = (builtins.tryEval (builtins.length packages.package-list)).success;

  reducedPackages = import "${src}/config/packages.nix" {
    hostname = "vulcan";
    inputs = builtins.removeAttrs downstreamInputs [ "git-all" ];
    pkgs = configured;
    isClientMachine = false;
  };
  acceptsReducedInputs =
    (builtins.tryEval (
      assert !(builtins.elem "git-all" reducedPackages.userPackageInputNames);
      builtins.length reducedPackages.package-list
    )).success;

  noIfdConfigured = configured // {
    haskellPackages = configured.haskellPackages // {
      callCabal2nix = throw "source-project applications must not use callCabal2nix during evaluation";
    };
  };
  noIfdPackages = import "${src}/config/packages.nix" {
    hostname = "vulcan";
    inputs = downstreamInputs;
    pkgs = noIfdConfigured;
    isClientMachine = false;
  };
  noIfdGitAll = configured.lib.findFirst (
    package: configured.lib.getName package == "git-all"
  ) null noIfdPackages.package-list;
  avoidsImportFromDerivation =
    (builtins.tryEval (
      assert noIfdGitAll != null;
      assert noIfdGitAll.src == inputs.git-all.outPath;
      assert noIfdGitAll.system == configured.stdenv.hostPlatform.system;
      noIfdGitAll.drvPath
    )).success;

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
assert configured.lib.assertMsg hasCanonicalCodex
  "downstream nix-config-ai consumers lost the canonical Codex package";
assert configured.lib.assertMsg hasManagedClaude
  "downstream nix-config-ai consumers lost the managed Claude wrapper";
assert configured.lib.assertMsg avoidsLegacyPackages
  "config/packages.nix reopened the stock nixpkgs package set for package predicates";
assert configured.lib.assertMsg acceptsReducedInputs
  "config/packages.nix requires the optional git-all input";
assert configured.lib.assertMsg avoidsImportFromDerivation
  "the git-all source projection used callCabal2nix during evaluation";
assert configured.lib.assertMsg degradesLoudly
  "config/packages.nix silently degraded managed agent wrappers without inputs.nix-config-ai";
pkgs.runCommand "managed-agent-package-selection" { } "touch $out"
