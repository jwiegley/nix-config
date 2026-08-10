{
  lib,
  pkgs,
  src,
}:

let
  rendererPkgs = pkgs // {
    agent-resources = "/catalog-agent-resources";
    pi-gallery = {
      outPath = "/catalog-pi-gallery";
      packages.pi-loop = "/catalog-pi-loop";
    };
  };
  catalog = import "${src}/config/ai/catalog.nix" {
    inherit lib;
    resources = "/catalog-agent-resources";
  };
  reject = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
  withMcpServers = mcpServers: catalog.items // { inherit mcpServers; };
  profiles = builtins.attrValues catalog.profiles;
  piProfiles = lib.filter (profile: profile.client == "pi") profiles;
  piProfile = lib.findFirst (profile: profile.client == "pi") (throw "Pi profile missing") profiles;
  droidProfile = lib.findFirst (
    profile: profile.client == "droid"
  ) (throw "Droid profile missing") profiles;
  stdioMcp = lib.findFirst (server: server.transport ? command) (throw "stdio MCP server missing") (
    builtins.attrValues catalog.items.mcpServers
  );
  syntheticHttpMcp = stdioMcp // {
    transport.url = "https://example.invalid/mcp";
    selectors.profiles = [ ];
  };
  unauthorizedHttpHeader = syntheticHttpMcp // {
    transport = syntheticHttpMcp.transport // {
      headers.Authorization.env = "OPENAI_API_KEY";
    };
  };
  mismatchedStdioEnvironment = stdioMcp // {
    transport = stdioMcp.transport // {
      env.SYNTHETIC_TOKEN.env = "OPENAI_API_KEY";
    };
  };
  missingHttpUrl = syntheticHttpMcp // {
    transport = { };
  };
  multipleUnauthorizedHttpHeaders = syntheticHttpMcp // {
    transport = syntheticHttpMcp.transport // {
      headers = {
        Authorization.env = "OPENAI_API_KEY";
        X-Synthetic-Token.env = "OPENAI_API_KEY";
      };
    };
  };
  selectFor = profile: lib.mapAttrs (_: itemSet: catalog.select profile itemSet) catalog.items;
  piRenderer = import "${src}/config/ai/renderers/pi.nix" {
    inherit lib;
    pkgs = rendererPkgs;
  };
  renderPi =
    profile:
    let
      darwin = profile.platform == "darwin";
      homeDirectory = if darwin then "/Users/test" else "/home/test";
    in
    {
      inherit profile darwin;
      rendered = piRenderer {
        inherit profile homeDirectory;
        selected = selectFor profile;
        xdgConfigHome = "${homeDirectory}/.config";
        passwordStoreDir = if darwin then "${homeDirectory}/doc/.password-store" else null;
        gnupgHome = if darwin then "${homeDirectory}/.config/gnupg" else null;
      };
    };
  piRenderings = map renderPi piProfiles;
  droidRendered =
    (import "${src}/config/ai/renderers/droid.nix" {
      inherit lib;
      pkgs = rendererPkgs;
    })
      {
        profile = droidProfile;
        selected = selectFor droidProfile;
        homeDirectory = "/Users/test";
        xdgConfigHome = "/Users/test/.config";
      };
in
assert catalog.validate { };
assert builtins.all (profile: (selectFor profile).mcpServers ? pal) profiles;
# The endpoint-bearing profile set drives generated codex TOML, pi local
# provider wiring, prime model overrides, and the dummy-key session
# variables; pin it so a gained or lost declaration is a visible test edit.
assert
  lib.sort builtins.lessThan (
    builtins.attrNames (
      lib.filterAttrs (_: profile: profile.localModelEndpoints != null) catalog.profiles
    )
  ) == [
    "clio-codex"
    "clio-pi"
    "hera-codex"
    "hera-pi"
    "hera-prime"
  ];
assert catalog.validate {
  items = withMcpServers (catalog.items.mcpServers // { synthetic-http = syntheticHttpMcp; });
};
assert piRenderings != [ ];
assert builtins.hasAttr "${droidProfile.root}/mcp.json" droidRendered.files;
assert builtins.all (
  entry:
  let
    files = entry.rendered.files;
  in
  builtins.hasAttr ".config/pi/agent/models.json" files
  && builtins.hasAttr ".config/mcp/mcp.json" files
  && (builtins.hasAttr ".config/pi/agent/model-router.json" files) == entry.darwin
  && entry.rendered.mutableMcpGuard.path == ".config/pi/agent/mcp.json"
) piRenderings;
assert builtins.all reject [
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { "../synthetic-http" = syntheticHttpMcp; });
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { synthetic-http = unauthorizedHttpHeader; });
  })
  (catalog.validate {
    items = withMcpServers (
      catalog.items.mcpServers // { synthetic-stdio = mismatchedStdioEnvironment; }
    );
  })
  (catalog.validate {
    items = withMcpServers (catalog.items.mcpServers // { synthetic-http = missingHttpUrl; });
  })
  (catalog.validate {
    items = withMcpServers (
      catalog.items.mcpServers // { synthetic-http = multipleUnauthorizedHttpHeaders; }
    );
  })
  (piRenderer {
    profile = piProfile // {
      client = "unsupported";
    };
    selected = selectFor piProfile;
    homeDirectory = "/Users/test";
    xdgConfigHome = "/Users/test/.config";
    passwordStoreDir = "/Users/test/doc/.password-store";
    gnupgHome = "/Users/test/.config/gnupg";
  })
];
pkgs.runCommand "ai-catalog-transport" { } ''
  ${lib.concatMapStringsSep "\n" (entry: ''
    ${pkgs.jq}/bin/jq -e '
      type == "object"
      and (.providers | type == "object")
    ' ${entry.rendered.files.".config/pi/agent/models.json".source} >/dev/null
    ${pkgs.jq}/bin/jq -e '
      type == "object"
      and (.mcpServers | type == "object")
    ' ${entry.rendered.files.".config/mcp/mcp.json".source} >/dev/null
  '') piRenderings}
  touch "$out"
''
