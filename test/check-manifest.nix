let
  platforms = {
    aarch64-darwin.ciRunner = "macos-15";
    aarch64-linux.ciRunner = "ubuntu-24.04-arm";
    x86_64-linux.ciRunner = "ubuntu-latest";
  };
  systems = builtins.attrNames platforms;
  darwinSystems = [ "aarch64-darwin" ];
  linuxSystems = [
    "aarch64-linux"
    "x86_64-linux"
  ];

  behavioral = supportedSystems: baseline: {
    kind = "behavioral";
    systems = supportedSystems;
    inherit baseline;
  };
  evaluationOnly = supportedSystems: {
    kind = "evaluation-only";
    systems = supportedSystems;
    baseline = false;
  };

  checks = {
    portable = {
      agent-deck-go-compat = evaluationOnly systems;
      agent-deck-runtime-lifecycle = behavioral systems false;
      agent-resources = behavioral systems true;
      agent-wrappers = behavioral systems true;
      build = behavioral systems false;
      compatibility-contract = evaluationOnly systems;
      format = behavioral systems false;
      fractal-smoke = behavioral systems false;
      lint = behavioral systems false;
      llama-cpp-platform-compat = evaluationOnly systems;
      llm-agents-nixpkgs-independent = evaluationOnly systems;
      llm-mlx-plugin = behavioral darwinSystems false;
      pi-extension-tests = behavioral systems true;
      pi-fleet-theme = behavioral systems true;
      pi-gallery = behavioral systems true;
      pi-session-replacement = behavioral systems false;
      prime-agent = behavioral systems false;
    };

    root = {
      agent-deck = behavioral systems false;
      ai-catalog-transport = behavioral systems true;
      ai-lock-coherence = evaluationOnly systems;
      ai-managed-preflight = behavioral systems false;
      coq-overlay = evaluationOnly systems;
      darwin-overrides-inactive = evaluationOnly linuxSystems;
      edit-env = behavioral systems false;
      emacs-head = evaluationOnly darwinSystems;
      home-manager-release-skew = behavioral systems false;
      host-behavior = evaluationOnly systems;
      managed-agent-package-selection = evaluationOnly systems;
      model-sync-state = behavioral systems false;
      obr-ownership = evaluationOnly systems;
      pi-blackhole-policy = behavioral systems false;
      syncthing = behavioral systems false;
    };
  };

  ownersFor =
    flake:
    if flake == "portable" then
      [ "portable" ]
    else if flake == "root" then
      [
        "portable"
        "root"
      ]
    else
      throw "unknown check-manifest flake: ${flake}";
  entriesFor =
    flake:
    builtins.concatLists (
      map (
        owner: map (name: checks.${owner}.${name} // { inherit name; }) (builtins.attrNames checks.${owner})
      ) (ownersFor flake)
    );
  namesFor =
    {
      flake,
      system,
      kind ? null,
      baselineOnly ? false,
    }:
    assert builtins.elem system systems || throw "unsupported check-manifest system: ${system}";
    builtins.sort builtins.lessThan (
      map (entry: entry.name) (
        builtins.filter (
          entry:
          builtins.elem system entry.systems
          && (kind == null || entry.kind == kind)
          && (!baselineOnly || entry.baseline)
        ) (entriesFor flake)
      )
    );
  difference = left: right: builtins.filter (name: !(builtins.elem name right)) left;
  validateDeclared =
    {
      flake,
      system,
      declared,
    }:
    let
      expected = namesFor { inherit flake system; };
      actual = builtins.sort builtins.lessThan (builtins.attrNames declared);
      unclassified = difference actual expected;
      undeclared = difference expected actual;
    in
    if actual == expected then
      true
    else
      throw ''
        ${flake} check manifest differs on ${system}
        declared but unclassified: ${builtins.concatStringsSep ", " unclassified}
        classified but undeclared: ${builtins.concatStringsSep ", " undeclared}
      '';
  ciMatrix = map (system: {
    inherit system;
    runner = platforms.${system}.ciRunner;
  }) systems;

in
assert builtins.all (value: builtins.match "[A-Za-z0-9_-]+" value != null) systems;
assert builtins.all (owner: checks.${owner} != { }) (builtins.attrNames checks);
assert builtins.all (
  owner:
  builtins.all (name: builtins.match "[A-Za-z0-9_-]+" name != null) (
    builtins.attrNames checks.${owner}
  )
) (builtins.attrNames checks);
assert builtins.all (
  owner:
  builtins.all (
    entry:
    entry.systems != [ ]
    && builtins.all (system: builtins.elem system systems) entry.systems
    && builtins.elem entry.kind [
      "behavioral"
      "evaluation-only"
    ]
    && (!entry.baseline || entry.kind == "behavioral")
  ) (builtins.attrValues checks.${owner})
) (builtins.attrNames checks);
{
  inherit
    ciMatrix
    checks
    namesFor
    systems
    validateDeclared
    ;
}
