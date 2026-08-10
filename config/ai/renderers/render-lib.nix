# Shared rendering helpers for the client renderers. One recognizer for typed
# environment references, one markdown front-matter format, and one command
# front-matter policy, so none of them can drift into per-client variants.
{ lib }:
let
  envReference = import ../env-reference.nix;

  renderMarkdownText =
    metadata: text: if metadata == { } then text else "---\n${builtins.toJSON metadata}\n---\n${text}";
in
{
  inherit (envReference) isTypedEnv;
  inherit renderMarkdownText;

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
