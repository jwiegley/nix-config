{
  inputs,
  actual,
}:

let
  contract = import ./compatibility-contract.nix;
  lib = inputs.nixpkgs.lib;
  sortedNames = value: lib.sort builtins.lessThan (builtins.attrNames value);
  inputNames = sortedNames (builtins.removeAttrs inputs [ "self" ]);
  outputNames = [
    "apps"
    "checks"
    "devShells"
    "formatter"
    "lib"
    "overlays"
    "packages"
  ];
  aliasesMatch = system: [
    (actual.apps.${system}.default == actual.apps.${system}.check)
    (actual.apps.${system}.coverage == actual.apps.${system}.test)
    (actual.apps.${system}.coverage-check == actual.apps.${system}.test)
    (actual.apps.${system}.fuzz == actual.apps.${system}.test)
    (actual.apps.${system}.memory-check == actual.apps.${system}.test)
    (actual.apps.${system}.profile == actual.apps.${system}.build-check)
    (actual.apps.${system}.profile-check == actual.apps.${system}.build-check)
    (actual.checks.${system}.coverage == actual.checks.${system}.tests)
    (actual.checks.${system}.fuzz == actual.checks.${system}.tests)
    (actual.checks.${system}.memory == actual.checks.${system}.tests)
    (actual.checks.${system}.profile == actual.checks.${system}.build)
  ];
  checkSystem =
    system:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ actual.overlays.default ];
      };
      overridden = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          actual.overlays.default
          (_final: _prev: { agent-deck = "caller-override"; })
        ];
      };
      sentinel = {
        passthrough = true;
      };
      representativePackages = [
        "agent-deck"
        "agent-http-header-bridge"
        "agent-resources"
        "claude-vault"
        "plasma-fractal"
        "plasma-wiki"
      ];
    in
    [
      (lib.assertMsg (
        sortedNames actual.packages.${system} == contract.packages
      ) "portable package contract changed for ${system}")
      (lib.assertMsg (
        sortedNames actual.apps.${system} == contract.apps
      ) "portable app contract changed for ${system}")
      (lib.assertMsg (
        sortedNames actual.checks.${system} == contract.checks
      ) "portable check contract changed for ${system}")
      (lib.assertMsg (
        sortedNames actual.devShells.${system} == [ "default" ]
      ) "portable dev shell contract changed for ${system}")
      (lib.assertMsg (builtins.all (
        name: pkgs ? ${name}
      ) representativePackages) "portable AI overlay lost representative packages on ${system}")
      (lib.assertMsg (
        overridden.agent-deck == "caller-override"
      ) "portable AI overlay prevents later caller overrides on ${system}")
      (lib.assertMsg (
        actual.lib.patchAgentPackage pkgs "unhandled" sentinel == sentinel
      ) "patchAgentPackage no longer passes unknown agents through on ${system}")
      (lib.assertMsg (builtins.isList (actual.lib.aiPackagesFor pkgs)) "aiPackagesFor no longer returns a package list on ${system}")
      (lib.assertMsg (
        actual.packages.${system}.default.name == "ai-nix-toolchain"
      ) "portable aggregate name changed on ${system}")
      (lib.assertMsg (
        actual.packages.${system}.plasma-fractal.version == "1.0.0"
      ) "plasma-fractal version changed on ${system}")
      (lib.assertMsg (
        actual.packages.${system}.plasma-wiki.version == "1.1.0"
      ) "plasma-wiki version changed on ${system}")
    ]
    ++ map (value: lib.assertMsg value "portable compatibility alias changed on ${system}") (
      aliasesMatch system
    );
  assertions = [
    (lib.assertMsg (inputNames == contract.inputs) "portable AI input contract changed")
    (lib.assertMsg (sortedNames actual == outputNames) "portable AI top-level output contract changed")
    (lib.assertMsg (
      sortedNames actual.lib == [
        "aiPackagesFor"
        "patchAgentPackage"
      ]
    ) "portable AI library contract changed")
    (lib.assertMsg (sortedNames actual.overlays == [ "default" ]) "portable overlay contract changed")
    (lib.assertMsg (builtins.isFunction actual.overlays.default) "portable default overlay is not callable")
    (lib.assertMsg (builtins.isFunction actual.lib.aiPackagesFor) "aiPackagesFor is not callable")
    (lib.assertMsg (builtins.isFunction actual.lib.patchAgentPackage) "patchAgentPackage is not callable")
    (lib.assertMsg (sortedNames actual.packages == contract.systems) "portable package systems changed")
    (lib.assertMsg (sortedNames actual.apps == contract.systems) "portable app systems changed")
    (lib.assertMsg (sortedNames actual.checks == contract.systems) "portable check systems changed")
    (lib.assertMsg (
      sortedNames actual.devShells == contract.systems
    ) "portable dev shell systems changed")
    (lib.assertMsg (
      sortedNames actual.formatter == contract.systems
    ) "portable formatter systems changed")
  ]
  ++ lib.concatMap checkSystem contract.systems;
  checked = actual // {
    checks = lib.mapAttrs (
      system: checks:
      checks
      // {
        compatibility-contract =
          (import inputs.nixpkgs { inherit system; }).runCommand "ai-compatibility-contract" { }
            "touch $out";
      }
    ) actual.checks;
  };
in
assert builtins.deepSeq assertions true;
checked
