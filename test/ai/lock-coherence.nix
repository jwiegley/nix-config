{ pkgs, src }:

let
  rootLock = builtins.fromJSON (builtins.readFile "${src}/flake.lock");
  portableLock = builtins.fromJSON (builtins.readFile "${src}/config/ai/flake.lock");
  rootAi = rootLock.nodes.${rootLock.nodes.root.inputs.nix-config-ai};
  portableRoot = portableLock.nodes.root;
  sharedInputs = builtins.attrNames portableRoot.inputs;
  locked =
    lock: node: name:
    lock.nodes.${node.inputs.${name}}.locked;
  coherent = builtins.all (
    name:
    builtins.hasAttr name rootAi.inputs
    && locked rootLock rootAi name == locked portableLock portableRoot name
  ) sharedInputs;
in
assert coherent || throw "root and portable AI lock nodes differ";
pkgs.runCommand "ai-lock-coherence" { } "touch $out"
