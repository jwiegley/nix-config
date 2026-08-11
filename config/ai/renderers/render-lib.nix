# Shared rendering helpers for the client renderers. One recognizer for typed
# environment references, one markdown front-matter format, and one command
# front-matter policy, so none of them can drift into per-client variants.
{ lib }:
let
  envReference = import ../env-reference.nix;

  renderMarkdownText =
    metadata: text: if metadata == { } then text else "---\n${builtins.toJSON metadata}\n---\n${text}";

  renderAgentCapabilities =
    mappings: capabilities:
    let
      known = map (mapping: mapping.capability) mappings;
    in
    assert builtins.isList capabilities;
    assert builtins.length known == builtins.length (lib.unique known);
    assert builtins.length capabilities == builtins.length (lib.unique capabilities);
    assert builtins.all (capability: builtins.elem capability known) capabilities;
    lib.concatMap (
      mapping: lib.optional (builtins.elem mapping.capability capabilities) mapping.output
    ) mappings;
in
{
  inherit (envReference) isTypedEnv;
  inherit renderAgentCapabilities renderMarkdownText;

  renderMarkdownFile = metadata: source: renderMarkdownText metadata (builtins.readFile source);

  # Front-matter policy for command prompts, shared by the Pi-compatible
  # clients. Closed key set; description and argument-hint are the only keys
  # projected into the generated document.
  renderCommandMetadata =
    item:
    assert builtins.all (
      name:
      builtins.elem name [
        "allowed-tools"
        "argument-hint"
        "description"
        "disable-model-invocation"
      ]
    ) (builtins.attrNames item.metadata);
    assert !(item.metadata ? description) || builtins.isString item.metadata.description;
    lib.optionalAttrs (item.metadata ? description) {
      inherit (item.metadata) description;
    }
    //
      lib.optionalAttrs
        (builtins.hasAttr "argument-hint" item.metadata && builtins.isString item.metadata."argument-hint")
        {
          "argument-hint" = item.metadata."argument-hint";
        };
}
