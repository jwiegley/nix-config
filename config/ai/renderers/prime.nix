{ lib, pkgs }:

{
  profile,
  selected,
  homeDirectory,
  xdgConfigHome,
}:

let
  root = ".prime/agent";
  json = pkgs.formats.json { };
  mergeFiles = import ./merge-files.nix { inherit lib; };
  modelOverrides = import ../model-overrides.nix;

  renderLib = import ./render-lib.nix { inherit lib; };
  inherit (renderLib) renderCommandMetadata;
  renderMarkdown = renderLib.renderMarkdownText;

  commandFiles = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/prompts/${name}.md" {
      text = renderMarkdown (renderCommandMetadata item) (builtins.readFile item.source);
    }
  ) selected.commands;
  promptFiles = lib.mapAttrs' (
    name: item: lib.nameValuePair "${root}/prompts/${name}.md" { inherit (item) source; }
  ) selected.prompts;
  agentFiles = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/prompts/agent-${name}.md" {
      text =
        renderMarkdown
          {
            description = item.metadata.description or "Spawn the managed ${name} specialist";
            argument-hint = "[task]";
          }
          ''
            Read the immutable specialist role at `${item.source}` in full. Then use Prime
            Agent's native `rlm` callable to spawn one persistent child without an explicit
            reusable name. Give the child that role followed by the user's task in
            `$ARGUMENTS`. Require the child to send its result to the parent with
            `agent_message`; do not treat the admission handle as the result. Continue
            independently or wait for that message as the task requires.
            ${lib.optionalString (item.metadata ? tools) ''
              Catalog tool policy (advisory in Prime Agent): ${item.metadata.tools}
            ''}
          '';
    }
  ) selected.agents;

  models.providers =
    modelOverrides.nativeProviders
    // lib.optionalAttrs (profile.localModelEndpoints != null) modelOverrides.localProviderOverrides;
  packageRoots = [
    "${pkgs.pi-gallery.packages.pi-provider-llama-swap}/share/pi-packages/pi-provider-llama-swap"
    "${pkgs.pi-gallery.packages.pi-provider-omlx}/share/pi-packages/pi-provider-omlx"
    "${pkgs.agent-resources}/share/agent-resources/pi-extensions/pi-mcp-adapter"
  ];
  settings = {
    skills = [ "-skill-creator/SKILL.md" ];
    defaultThinkingLevel = "xhigh";
    enableBuiltinSkills = true;
    enableSkillCommands = true;
    packages = packageRoots;
    theme = "dark-tool-backgrounds";
  };
  keybindings = import ../keybindings.nix;
  baseTheme = builtins.fromJSON (builtins.readFile ../themes/dark-tool-backgrounds.json);
  primeTheme = baseTheme // {
    vars = baseTheme.vars // {
      toolDiffAddedBg = "#015f00";
      toolDiffRemovedBg = "#5e0000";
    };
    colors = (builtins.removeAttrs baseTheme.colors [ "thinkingMax" ]) // {
      toolDiffAddedBg = "toolDiffAddedBg";
      toolDiffRemovedBg = "toolDiffRemovedBg";
      toolDiffText = "#9aa0a6";
      toolPanelBg = "#262630";
    };
  };
  compatibility = ''
    # Nix-managed Prime Agent compatibility

    Prime Agent uses the same catalog-selected prompt commands, prompt templates, and
    Agent Skills as the other managed clients. Specialist definitions are exposed as
    `/agent-<name>` RLM prompt adapters because Prime Agent has no declarative static-agent
    file loader. Per-agent tool allowlists are advisory role text rather than enforced child
    policies.

    The managed model file preserves safe built-in-provider context overrides. Local model
    discovery reuses the existing generic provider extensions. The secret-command-backed
    provider and the Pi model router are intentionally omitted.

    Prime Agent's native MCP layer does not support local stdio servers. The managed
    `pi-mcp-adapter` package supplies those servers from the standard Nix-generated MCP file
    beneath `XDG_CONFIG_HOME`; Prime's private agent root remains `.prime/agent`.
    Pi-specific session, goal, compaction, gallery, and subagent extensions are intentionally
    excluded because Prime Agent owns those lifecycles natively. Prime Agent's built-in
    `skill-creator` is disabled in favor of the shared managed skill with the same name.

    Selected resources: ${toString (builtins.length (builtins.attrNames selected.commands))}
    commands, ${toString (builtins.length (builtins.attrNames selected.prompts))} prompts,
    ${toString (builtins.length (builtins.attrNames selected.agents))} specialist adapters,
    ${toString (builtins.length (builtins.attrNames selected.skills))} skills selected for
    this profile (the shared `.agents/skills` root carries the union across the
    Pi-compatible clients), and
    ${toString (builtins.length (builtins.attrNames selected.mcpServers))} MCP servers.
  '';
in
assert profile.client == "prime";
assert profile.root == root;
assert profile.host == "hera";
assert profile.platform == "darwin";
assert builtins.isString homeDirectory;
assert xdgConfigHome == "${homeDirectory}/.config";
assert selected.hooks == { };
assert selected.marketplaces == { };
assert selected.settings == { };
assert
  lib.intersectLists (builtins.attrNames selected.commands) (builtins.attrNames selected.prompts)
  == [ ];
assert
  lib.intersectLists (map (name: "agent-${name}") (builtins.attrNames selected.agents)) (
    builtins.attrNames selected.commands
  ) == [ ];
assert builtins.hasAttr "agent-resources" pkgs;
assert builtins.hasAttr "pi-gallery" pkgs;
{
  files = mergeFiles [
    agentFiles
    commandFiles
    promptFiles
    {
      "${root}/COMPATIBILITY.md".text = compatibility;
      "${root}/keybindings.json".source =
        json.generate "prime-${profile.id}-keybindings.json" keybindings;
      "${root}/models.json".source = json.generate "prime-${profile.id}-models.json" models;
      "${root}/managed-settings.json".source =
        json.generate "prime-${profile.id}-managed-settings.json" settings;
      "${root}/themes/dark-tool-backgrounds.json".source =
        json.generate "prime-${profile.id}-theme.json" primeTheme;
    }
  ];
}
