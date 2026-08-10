{
  inputs,
  actual,
}:

let
  contract = import ./compatibility-contract.nix;
  lib = inputs.nixpkgs.lib;
  sortedNames = value: lib.sort builtins.lessThan (builtins.attrNames value);
  hasAll = actual: required: builtins.all (name: builtins.elem name actual) required;
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
  # `default == check` is the only alias worth pinning: it is a convention, and it
  # claims no evidence of its own. The eleven pins removed here did the opposite —
  # they froze names like `coverage`, `fuzz`, `memory` and `profile` to whatever
  # they aliased (tests/build), guaranteeing the names could never start meaning
  # what they said. A contract that forbids a lie from being corrected is worse
  # than no contract. See jwiegley/nix-config#48.
  aliasesMatch = system: [
    (actual.apps.${system}.default == actual.apps.${system}.check)
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
      consumerBunSentinel = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          (_final: _prev: {
            bun = pinnedCmBun.overrideAttrs (_old: {
              CM_CONSUMER_SENTINEL = "1";
            });
          })
          actual.overlays.default
        ];
      };
      pinnedCmBun = inputs.cm-bun-nixpkgs.legacyPackages.${system}.bun;
      pinnedPiPackage = inputs.pi-llm-agents.packages.${system}.pi;
      toolPkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ actual.overlays.tools ];
      };
      consumerTools = [
        "filetags"
        "hammer"
        "linkdups"
        "lipotell"
        "markless"
        "nix-scripts"
        "tsvutils"
      ];
      sentinel = {
        passthrough = true;
      };
      representativePackages = [
        "agent-deck"
        "agent-http-header-bridge"
        "agent-resources"
        "claude-vault"
        "pal-mcp-server"
        "plasma-fractal"
        "plasma-wiki"
      ];
    in
    [
      (lib.assertMsg (hasAll (sortedNames
        actual.packages.${system}
      ) contract.packages) "portable package contract lost a required package for ${system}")
      (lib.assertMsg (hasAll (sortedNames
        actual.apps.${system}
      ) contract.apps) "portable app contract lost a required app for ${system}")
      (lib.assertMsg (hasAll (sortedNames
        actual.checks.${system}
      ) contract.checks) "portable check contract lost a required check for ${system}")
      (lib.assertMsg (builtins.hasAttr "default"
        actual.devShells.${system}
      ) "portable default dev shell is missing for ${system}")
      (lib.assertMsg (builtins.all (
        name: pkgs ? ${name}
      ) representativePackages) "portable AI overlay lost representative packages on ${system}")
      (lib.assertMsg (
        pkgs ? pal-mcp-server
        && builtins.any (package: package.drvPath == pkgs.pal-mcp-server.drvPath) (
          actual.lib.aiPackagesFor pkgs
        )
      ) "portable AI package policy lost PAL on ${system}")
      (lib.assertMsg (
        overridden.agent-deck == "caller-override"
      ) "portable AI overlay prevents later caller overrides on ${system}")
      (lib.assertMsg (
        pkgs.agent-deck.passthru.runtimeLifecycleRaceEnabled == (system != "aarch64-linux")
      ) "agent-deck lifecycle race policy changed on ${system}")
      (lib.assertMsg (builtins.all (
        name: toolPkgs ? ${name}
      ) consumerTools) "portable tools overlay lost a supported consumer package on ${system}")
      (lib.assertMsg (
        toolPkgs.nix-scripts.drvPath == actual.packages.${system}.nix-scripts.drvPath
      ) "portable nix-scripts package and tools overlay diverged on ${system}")
      (lib.assertMsg (
        actual.lib.patchAgentPackage pkgs "unhandled" sentinel == sentinel
      ) "patchAgentPackage no longer passes unknown agents through on ${system}")
      (lib.assertMsg (builtins.isList (actual.lib.aiPackagesFor pkgs)) "aiPackagesFor no longer returns a package list on ${system}")
      (lib.assertMsg (
        actual.packages.${system}.default.name == "ai-nix-toolchain"
      ) "portable aggregate name changed on ${system}")
      (lib.assertMsg (
        actual.packages.${system}.cm.passthru.buildBun.version == "1.3.13"
      ) "portable cm lost its pinned Bun 1.3.13 build tool on ${system}")
      (lib.assertMsg (
        actual.packages.${system}.pi.drvPath == (actual.lib.patchAgentPackage pkgs "pi" pinnedPiPackage)
        .drvPath
      ) "portable Pi moved away from its pinned packaging substrate on ${system}")
      (lib.assertMsg (builtins.any (package: package.drvPath == actual.packages.${system}.pi.drvPath) (
        actual.lib.aiPackagesFor pkgs
      )) "portable AI package policy lost the canonical pinned Pi on ${system}")
      (lib.assertMsg (
        consumerBunSentinel.bun.version == pinnedCmBun.version
        && consumerBunSentinel.bun.drvPath != pinnedCmBun.drvPath
        && consumerBunSentinel.cm.passthru.buildBun.drvPath == pinnedCmBun.drvPath
      ) "portable cm no longer isolates its Bun from the consumer package set on ${system}")
    ]
    ++ map (value: lib.assertMsg value "portable compatibility alias changed on ${system}") (
      aliasesMatch system
    );
  # The two pins are guarded by a division of labor. The `.rev` literals below
  # are test-owned tripwires: an exact-rev flake URL cannot drift on its own,
  # but editing it moves the input AND both locks together, so only a literal
  # held here forces a pin change to be a deliberate two-place edit. What the
  # literals cannot see, construction-level checks cover: the per-system Pi
  # drvPath assertion catches Pi being packaged from any feed other than
  # `pi-llm-agents` or bypassing `patchAgentPackage`, and the cm sentinel
  # assertions catch its pinned Bun leaking to or from the consumer channel.
  assertions = [
    (lib.assertMsg (
      inputs.cm-bun-nixpkgs.rev == "a5e9f2fd9ef6011c6886d6935f3ef678c81385fa"
    ) "portable cm Bun input moved from its reviewed Nixpkgs revision")
    (lib.assertMsg (
      inputs.pi-llm-agents.rev == "f99bb437fd6860f23ea6c67a5161578a3b89d856"
    ) "portable Pi packaging input moved from its reviewed llm-agents revision")
    (lib.assertMsg (hasAll inputNames contract.inputs) "portable AI input contract lost a required input")
    (lib.assertMsg (hasAll (sortedNames actual) outputNames) "portable AI top-level output contract lost a required output")
    (lib.assertMsg (builtins.isFunction actual.overlays.default) "portable default overlay is not callable")
    (lib.assertMsg (builtins.isFunction actual.overlays.tools) "portable tools overlay is not callable")
    (lib.assertMsg (builtins.isFunction actual.lib.aiPackagesFor) "aiPackagesFor is not callable")
    (lib.assertMsg (builtins.isFunction actual.lib.patchAgentPackage) "patchAgentPackage is not callable")
    (lib.assertMsg (hasAll (sortedNames actual.packages) contract.systems) "portable packages lost a required system")
    (lib.assertMsg (hasAll (sortedNames actual.apps) contract.systems) "portable apps lost a required system")
    (lib.assertMsg (hasAll (sortedNames actual.checks) contract.systems) "portable checks lost a required system")
    (lib.assertMsg (hasAll (sortedNames actual.devShells) contract.systems) "portable dev shells lost a required system")
    (lib.assertMsg (hasAll (sortedNames actual.formatter) contract.systems) "portable formatter lost a required system")
  ];
  # Fail-closed, scoped to the system being consumed: reading any system's
  # packages, apps, devShells, or checks forces the global assertions plus
  # that ONE system's contract sweep. Activation paths (`darwin-rebuild
  # switch`, `./build system`, remote consumer switches) therefore cannot
  # consume a contract-violating output, while no consumer pays the other
  # systems' sweeps. Cross-system coverage is owned by
  # `nix flake check --all-systems` — run by test/bin/quality's portable-eval
  # suite (expensive tier) and .github/workflows/portable-assurance.yml; a
  # bare `nix flake check` covers only the host system. `overlays` and `lib`
  # are system-agnostic and stay unguarded; every supported consumer reads
  # `packages.<system>` and so passes through the guard.
  contractFor = lib.genAttrs contract.systems (system: assertions ++ checkSystem system);
  guard =
    system: outputs:
    assert builtins.deepSeq (contractFor.${system} or [ ]) true;
    outputs;
  checked = actual // {
    packages = lib.mapAttrs guard actual.packages;
    apps = lib.mapAttrs guard actual.apps;
    devShells = lib.mapAttrs guard actual.devShells;
    checks = lib.mapAttrs (
      system: checks:
      guard system (
        checks
        // {
          compatibility-contract =
            (import inputs.nixpkgs { inherit system; }).runCommand "ai-compatibility-contract" { }
              "touch $out";
        }
      )
    ) actual.checks;
  };
in
checked
