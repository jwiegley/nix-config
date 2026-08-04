{
  inputs,
  pkgs,
}:

let
  aiSources = import ../../packages/source-catalog.nix "ai";
  piSources = import ../../packages/source-catalog.nix "pi";
  projections = {
    inherit (aiSources)
      git-ai
      llm-agents
      mcp-remote
      mcp-servers-nix
      pal-mcp-server
      rust-overlay
      translate-tool
      ;
    inherit (piSources)
      pi-mcp-adapter
      pi-openai-server-compaction
      pi-quiet
      ;
  };
  expectedNames = [
    "git-ai"
    "llm-agents"
    "mcp-remote"
    "mcp-servers-nix"
    "pal-mcp-server"
    "pi-mcp-adapter"
    "pi-openai-server-compaction"
    "pi-quiet"
    "rust-overlay"
    "translate-tool"
  ];
  lock = builtins.fromJSON (builtins.readFile ../../config/ai/flake.lock);
  root = lock.nodes.${lock.root};
  same =
    name: field: actual: expected:
    if actual == expected then true else throw "input projection ${name} ${field} mismatch";
  check =
    name:
    let
      record = projections.${name};
      inputName = record.update.input;
      nodeReference = root.inputs.${inputName};
      node =
        if builtins.isString nodeReference then
          lock.nodes.${nodeReference}
        else
          throw "input projection ${name} does not select one portable lock node";
      inherit (node) locked original;
      expected = record.source.args;
      evaluated = inputs.${inputName};
    in
    builtins.all (value: value) [
      (same name "input name" inputName name)
      (same name "source URL" record.source.url "https://github.com/${expected.owner}/${expected.repo}")
      (same name "locked type" expected.type locked.type)
      (same name "locked owner" expected.owner locked.owner)
      (same name "locked repo" expected.repo locked.repo)
      (same name "locked rev" expected.rev locked.rev)
      (same name "locked narHash" expected.narHash locked.narHash)
      (same name "declared type" expected.type original.type)
      (same name "declared owner" expected.owner original.owner)
      (same name "declared repo" expected.repo original.repo)
      (if original ? rev then same name "declared rev" expected.rev original.rev else true)
      (same name "evaluated rev" expected.rev evaluated.rev)
      (same name "evaluated narHash" expected.narHash evaluated.narHash)
    ];
in
assert builtins.attrNames projections == expectedNames;
assert builtins.all check expectedNames;
pkgs.runCommand "input-projection-parity" { } "touch $out"
