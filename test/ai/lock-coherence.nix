{ pkgs, src }:

let
  rootLock = builtins.fromJSON (builtins.readFile "${src}/flake.lock");
  portableLock = builtins.fromJSON (builtins.readFile "${src}/config/fleet/flake.lock");
  rootAi = rootLock.nodes.${rootLock.nodes.root.inputs.nix-config-ai};
  portableRoot = portableLock.nodes.root;
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
in
assert coherent || throw "root and portable AI lock nodes differ";
pkgs.runCommand "ai-lock-coherence" { } "touch $out"
