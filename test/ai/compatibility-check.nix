{
  inputs,
  actual,
}:

let
  checkManifest = import ../check-manifest.nix;
  contract = import ./compatibility-contract.nix;
  lib = inputs.nixpkgs.lib;
  sources = import ../../packages/source-catalog.nix "ai";
  implementationSource = builtins.readFile ../../flake/ai.nix;
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
      pinnedCodexPackage = inputs.llm-agents.packages.${system}.codex;
      upstreamPiPackage = inputs.llm-agents.packages.${system}.pi;
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
        "agent-resources"
        "claude-vault"
        "pal-mcp-server"
        "plasma-fractal"
        "plasma-wiki"
      ];
      gitAiDrvPaths = map (package: package.drvPath) (
        builtins.attrValues inputs.git-ai.packages.${system}
      );
      mlxVlm313 = pkgs.python313Packages.mlx-vlm;
      mlxVlm314 = pkgs.python314Packages.mlx-vlm;
      ddgs313 = pkgs.python313Packages.ddgs;
      ddgs314 = pkgs.python314Packages.ddgs;
      lacksGitAiReference = package: !(builtins.elem package.drvPath gitAiDrvPaths);
      activePackageSelections =
        actual.lib.aiPackagesFor pkgs
        ++ (actual.devShells.${system}.default.buildInputs or [ ])
        ++ (actual.devShells.${system}.default.nativeBuildInputs or [ ]);
      expectedAggregate = pkgs.buildEnv {
        name = "ai-nix-toolchain";
        paths = actual.lib.aiPackagesFor pkgs;
        ignoreCollisions = true;
      };
      declaredChecks = actual.checks.${system} // {
        # The wrapper below adds this evaluation-only gate after checking the
        # implementation. A placeholder lets every guarded output validate the
        # final public check surface without constructing the derivation twice.
        compatibility-contract = null;
      };
    in
    [
      (checkManifest.validateDeclared {
        flake = "portable";
        declared = declaredChecks;
        inherit system;
      })
      (lib.assertMsg (hasAll (sortedNames
        actual.packages.${system}
      ) contract.packages) "portable package contract lost a required package for ${system}")
      (lib.assertMsg (hasAll (sortedNames
        actual.apps.${system}
      ) contract.apps) "portable app contract lost a required app for ${system}")
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
        system != "aarch64-darwin"
        || (mlxVlm313.version == sources.mlx-vlm.version && mlxVlm314.version == sources.mlx-vlm.version)
      ) "mlx-vlm package variants diverged from the catalog on ${system}")
      (lib.assertMsg (
        system != "aarch64-darwin"
        || (ddgs313.version == sources.ddgs.version && ddgs314.version == sources.ddgs.version)
      ) "DDGS package variants diverged from the catalog on ${system}")
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
        toolPkgs.nix-scripts.meta.license.spdxId == "BSD-3-Clause"
      ) "portable nix-scripts package lost its BSD-3-Clause SPDX metadata on ${system}")
      (lib.assertMsg (
        !(toolPkgs.nix-scripts.meta ? homepage)
      ) "portable nix-scripts package advertises a non-authoritative homepage on ${system}")
      (lib.assertMsg (
        actual.lib.patchAgentPackage pkgs "unhandled" sentinel == sentinel
      ) "patchAgentPackage no longer passes unknown agents through on ${system}")
      (lib.assertMsg (builtins.isList (actual.lib.aiPackagesFor pkgs)) "aiPackagesFor no longer returns a package list on ${system}")
      (lib.assertMsg (gitAiDrvPaths != [ ]) "portable Git-AI reference oracle is empty on ${system}")
      (lib.assertMsg (builtins.all lacksGitAiReference activePackageSelections) "portable package policy or dev shell references dormant Git-AI on ${system}")
      (lib.assertMsg (
        actual.packages.${system}.default.drvPath == expectedAggregate.drvPath
        && actual.checks.${system}.build.drvPath == expectedAggregate.drvPath
      ) "portable aggregate or build check diverged from the Git-AI-free package policy on ${system}")
      (lib.assertMsg (
        actual.packages.${system}.default.name == "ai-nix-toolchain"
      ) "portable aggregate name changed on ${system}")
      (lib.assertMsg (
        actual.packages.${system}.codex.drvPath
        == (actual.lib.patchAgentPackage pkgs "codex" pinnedCodexPackage).drvPath
      ) "portable Codex moved away from its canonical packaging substrate on ${system}")
      (lib.assertMsg (builtins.any (package: package.drvPath == actual.packages.${system}.codex.drvPath) (
        actual.lib.aiPackagesFor pkgs
      )) "portable AI package policy lost the canonical Codex on ${system}")
      (lib.assertMsg (
        actual.packages.${system}.pi.drvPath == (actual.lib.patchAgentPackage pkgs "pi" upstreamPiPackage)
        .drvPath
      ) "portable Pi moved away from its canonical packaging substrate on ${system}")
      (lib.assertMsg (builtins.any (package: package.drvPath == actual.packages.${system}.pi.drvPath) (
        actual.lib.aiPackagesFor pkgs
      )) "portable AI package policy lost the canonical Pi on ${system}")
    ]
    ++ map (value: lib.assertMsg value "portable compatibility alias changed on ${system}") (
      aliasesMatch system
    );
  assertions = [
    (lib.assertMsg (hasAll inputNames contract.inputs) "portable AI input contract lost a required input")
    (lib.assertMsg (hasAll (sortedNames actual) outputNames) "portable AI top-level output contract lost a required output")
    (lib.assertMsg (builtins.isFunction actual.overlays.default) "portable default overlay is not callable")
    (lib.assertMsg (builtins.isFunction actual.overlays.tools) "portable tools overlay is not callable")
    (lib.assertMsg (builtins.isFunction actual.lib.aiPackagesFor) "aiPackagesFor is not callable")
    (lib.assertMsg (builtins.isFunction actual.lib.optAgent) "optAgent is not callable")
    (lib.assertMsg (builtins.isFunction actual.lib.patchAgentPackage) "patchAgentPackage is not callable")
    # Package-set identity is an evaluation-cost property that output equality
    # cannot observe, so keep this one contract source-based.
    (lib.assertMsg (
      lib.hasInfix "pkgsFor = forAllSystems mkPkgs;" implementationSource
      && !(lib.hasInfix "pkgs = mkPkgs system;" implementationSource)
    ) "portable outputs reopened the primary nixpkgs package set")
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
      let
        declared = checks // {
          compatibility-contract =
            (import inputs.nixpkgs { inherit system; }).runCommand "ai-compatibility-contract" { }
              ''
                test -x ${actual.packages.${system}.nix-scripts}/bin/upgrade-projects
                touch $out
              '';
        };
      in
      guard system declared
    ) actual.checks;
  };
in
checked
