{ pkgs, src }:

let
  rootSource = builtins.readFile "${src}/flake.nix";
  rootLock = builtins.fromJSON (builtins.readFile "${src}/flake.lock");
  portableLock = builtins.fromJSON (builtins.readFile "${src}/config/ai/flake.lock");
  rootAi = rootLock.nodes.${rootLock.nodes.root.inputs.nix-config-ai};
  portableRoot = portableLock.nodes.root;
  rootGitAi = rootLock.nodes.${rootAi.inputs.git-ai};
  portableGitAi = portableLock.nodes.${portableRoot.inputs.git-ai};
  followNode =
    lock: path:
    builtins.foldl' (
      nodeName: inputName:
      let
        reference = lock.nodes.${nodeName}.inputs.${inputName};
      in
      if builtins.isString reference then reference else followNode lock reference
    ) "root" path;
  canonicalReference =
    lock: reference:
    canonicalNode lock (if builtins.isString reference then reference else followNode lock reference);
  canonicalNode =
    lock: name:
    let
      node = lock.nodes.${name};
    in
    {
      flake = node.flake or true;
      locked = node.locked or null;
      inputs = builtins.mapAttrs (_: canonicalReference lock) (node.inputs or { });
    };
  canonicalInputs = lock: node: builtins.mapAttrs (_: canonicalReference lock) (node.inputs or { });
  coherent = canonicalInputs rootLock rootAi == canonicalInputs portableLock portableRoot;
  gitAiReusesPortableRustOverlay =
    portableGitAi.inputs.rust-overlay == [ "rust-overlay" ]
    &&
      rootGitAi.inputs.rust-overlay == [
        "nix-config-ai"
        "rust-overlay"
      ];
  reusesPortableInput =
    pkgs.lib.hasInfix "portableAi = rootInputs.nix-config-ai;" rootSource
    && !(pkgs.lib.hasInfix "import ./flake/ai.nix" rootSource)
    && !(pkgs.lib.hasInfix "import ./config/ai/flake.nix" rootSource);
in
assert coherent || throw "root and portable AI lock nodes differ";
assert
  gitAiReusesPortableRustOverlay || throw "Git-AI does not follow the canonical rust-overlay input";
assert reusesPortableInput || throw "root flake rebuilt the already-instantiated portable AI input";
pkgs.runCommand "ai-lock-coherence" { } "touch $out"
