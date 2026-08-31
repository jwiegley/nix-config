{
  lib,
  pkgs,
  localProviderTransportPolicy ? import ../local-provider-transport.nix,
}:

{
  profile,
  selected,
  homeDirectory,
  xdgConfigHome,
  passwordStoreDir,
  gnupgHome,
  localModelEndpoints,
  localModelDiscoveryEndpoints,
}:

let
  root = ".config/pi/agent";
  json = pkgs.formats.json { };
  mergeFiles = import ./merge-files.nix { inherit lib; };

  renderLib = import ./render-lib.nix { inherit lib; };
  inherit (renderLib) renderCommandMetadata;
  renderMarkdown = renderLib.renderMarkdownFile;

  hasOnlyKeys =
    allowed: value: builtins.all (name: builtins.elem name allowed) (builtins.attrNames value);
  localModelRoutes = localModelEndpoints != null;
  localModelDiscovery = localModelDiscoveryEndpoints != null;
  inherit (profile) hermesRoute;
  modelOverrides = import ../model-overrides.nix;
  fastModeConfig = import ../pi-gpt-fast-mode.nix;
  projectProviderEndpoints = import ./project-provider-endpoints.nix { inherit lib; };
  hermesPassCommand = lib.escapeShellArgs [
    "${pkgs.coreutils}/bin/env"
    "-u"
    "GPG_TTY"
    "PASSWORD_STORE_DIR=${passwordStoreDir}"
    "GNUPGHOME=${gnupgHome}"
    "${pkgs.pass}/bin/pass"
    "api.hermes.com"
  ];
  hermesApiKeyScript = "secret=\"$(${hermesPassCommand})\" || exit; ${pkgs.coreutils}/bin/printf \"%s\\n\" \"$secret\" | ${pkgs.coreutils}/bin/head -n 1";
  hermesApiKeyCommand = "!${pkgs.bash}/bin/bash -c ${lib.escapeShellArg hermesApiKeyScript}";

  inherit (modelOverrides) nativeProviders;
  # Slow local inference owns its budgets; the global client defaults remain ordinary.
  localProviderTransport = {
    requestTimeoutMs = localProviderTransportPolicy.client.requestTimeoutMilliseconds;
    idleTimeoutMs = localProviderTransportPolicy.client.streamIdleTimeoutMilliseconds;
  };
  localModelDiscoveryProviderNames =
    if localModelDiscovery then builtins.attrNames localModelDiscoveryEndpoints else [ ];
  localProviderOverrides = lib.getAttrs localModelDiscoveryProviderNames modelOverrides.pi.localProviderOverrides;
  galleryProviderDefinitions = lib.getAttrs localModelDiscoveryProviderNames modelOverrides.pi.galleryProviders;
  galleryEndpointsByOwner =
    if localModelDiscovery then
      projectProviderEndpoints {
        definitions = galleryProviderDefinitions;
        endpoints = localModelDiscoveryEndpoints;
      }
    else
      { };
  hermesProvider = {
    hermes = {
      api = "openai-completions";
      apiKey = hermesApiKeyCommand;
      baseUrl = "https://hermes.vulcan.lan/v1";
      compat.sendSessionAffinityHeaders = true;
      models = [ { id = "hermes-agent"; } ];
    };
  };
  localProviders = lib.mapAttrs (
    _: provider: provider // { transport = localProviderTransport; }
  ) localProviderOverrides;
  localDiscoveryProviders = lib.mapAttrs (_: _: { transport = localProviderTransport; }) (
    if localModelDiscovery then localModelDiscoveryEndpoints else { }
  );
  gallerySource = pkgs.writeText "pi-managed-gallery.ts" ''
    import { createNixGallery } from ${builtins.toJSON "${pkgs.pi-gallery}/share/pi-gallery/loader.ts"};

    export default createNixGallery(${builtins.toJSON galleryEndpointsByOwner});
  '';
  galleryRoot = pkgs.runCommand "pi-managed-gallery" { } ''
    mkdir -p "$out"
    cp ${gallerySource} "$out/index.ts"
    ln -s ${pkgs.pi-gallery}/share/pi-gallery/projection.json "$out/projection.json"
  '';
  models.providers =
    nativeProviders
    // lib.optionalAttrs localModelDiscovery localDiscoveryProviders
    // lib.optionalAttrs hermesRoute hermesProvider
    // lib.optionalAttrs localModelRoutes localProviders;
  providerApiKeyForms = lib.mapAttrs (_: provider: provider.apiKey) (
    lib.filterAttrs (_: provider: provider ? apiKey) models.providers
  );
  # Closed security boundary: adding or changing any apiKey-bearing provider
  # requires an explicit policy edit here.
  approvedProviderApiKeyForms = lib.optionalAttrs hermesRoute { hermes = hermesApiKeyCommand; };

  keybindings = import ../keybindings.nix // {
    # Pi-specific: model cycling is disabled in favor of explicit selection.
    "app.model.cycleForward" = [ ];
    "app.model.cycleBackward" = [ ];
  };

  piAgentCapabilities = [
    {
      capability = "read-files";
      output = "read";
    }
    {
      capability = "search-text";
      output = "grep";
    }
    {
      capability = "find-files";
      output = "find";
    }
    {
      capability = "run-commands";
      output = "bash";
    }
  ];
  renderAgentMetadata =
    item:
    assert hasOnlyKeys [
      "capabilities"
      "description"
      "name"
    ] item.metadata;
    builtins.removeAttrs item.metadata [ "capabilities" ]
    // lib.optionalAttrs (item.metadata ? capabilities) {
      tools = lib.concatStringsSep "," (
        renderLib.renderAgentCapabilities piAgentCapabilities item.metadata.capabilities
      );
    };

  agentFiles = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/agents/${name}.md" {
      text = renderMarkdown (renderAgentMetadata item) item.source;
    }
  ) selected.agents;
  commandFiles = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/prompts/${name}.md" {
      text = renderMarkdown (renderCommandMetadata item) item.source;
    }
  ) selected.commands;
  promptFiles = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/prompts/${name}.md" {
      inherit (item) source;
    }
  ) selected.prompts;

  extensionRoot = "${pkgs.agent-resources}/share/agent-resources/pi-extensions";
  fleetThemeSource = ../extensions/fleet-theme/index.ts;
  fleetTheme = ../themes/dark-tool-backgrounds.json;
in
assert profile.client == "pi";
assert profile.root == root;
assert profile.localModelRoutes == localModelRoutes;
assert localModelDiscovery == (profile.platform == "darwin" || profile.id == "vulcan-pi");
assert
  !localModelDiscovery
  || builtins.attrNames localModelDiscoveryEndpoints == builtins.attrNames localProviderOverrides;
assert
  !localModelDiscovery
  || builtins.attrNames localModelDiscoveryEndpoints == builtins.attrNames galleryProviderDefinitions;
assert builtins.isBool hermesRoute;
assert builtins.isString homeDirectory;
assert xdgConfigHome == "${homeDirectory}/.config";
assert !hermesRoute || (builtins.isString passwordStoreDir && builtins.isString gnupgHome);
assert lib.assertMsg (
  providerApiKeyForms == approvedProviderApiKeyForms
) "Pi model-provider apiKey fields escaped the closed Hermes-command set";
assert selected.hooks == { };
assert selected.marketplaces == { };
assert selected.settings == { };
assert
  lib.intersectLists (builtins.attrNames selected.commands) (builtins.attrNames selected.prompts)
  == [ ];
assert builtins.hasAttr "agent-resources" pkgs;
assert builtins.hasAttr "pi-gallery" pkgs;
assert builtins.hasAttr "pi-loop" pkgs.pi-gallery.packages;
assert builtins.hasAttr "pi-gpt-fast-mode" pkgs.pi-gallery.packages;
{
  files = mergeFiles [
    agentFiles
    commandFiles
    promptFiles
    {
      ".pi-lens/config.json".source = json.generate "pi-${profile.id}-lens.json" {
        widget.visible = false;
      };
      "${root}/extensions/fleet-theme/index.ts".source = fleetThemeSource;
      "${root}/extensions/nix-gallery/index.ts".source = "${galleryRoot}/index.ts";
      "${root}/extensions/pi-gpt-fast-mode/config.json".source =
        json.generate "pi-${profile.id}-gpt-fast-mode.json" fastModeConfig;
      "${root}/extensions/pi-loop/index.ts".source =
        "${pkgs.pi-gallery.packages.pi-loop}/share/pi-packages/pi-loop/extensions/index.ts";
      "${root}/extensions/pi-mcp-adapter".source = "${extensionRoot}/pi-mcp-adapter";
      "${root}/extensions/pi-quiet".source = "${extensionRoot}/pi-quiet";
      "${root}/keybindings.json".source = json.generate "pi-${profile.id}-keybindings.json" keybindings;
      "${root}/models.json".source = json.generate "pi-${profile.id}-models.json" models;
      "${root}/themes/dark-tool-backgrounds.json".source = fleetTheme;
    }
  ];
}
