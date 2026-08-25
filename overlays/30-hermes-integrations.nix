{ inputs }:
final: _previous:

let
  hermesAgentPackage = inputs.hermes-agent.packages.${final.stdenv.hostPlatform.system}.default;
  hermesOrgJw = final.haskell.lib.overrideCabal sourceProjectApps.org-jw (old: {
    patches = (old.patches or [ ]) ++ [ ../packages/hermes-org-db-mcp/org-jw-query-stdin.patch ];
  });
  sourceProjectApps = import ../packages/source-project-apps.nix {
    inherit inputs;
    pkgs = final;
  };
in
{
  hermes-local-extract = final.callPackage ../packages/hermes-local-extract {
    inherit hermesAgentPackage;
  };
  hermes-org-db-mcp = final.callPackage ../packages/hermes-org-db-mcp {
    org-jw = hermesOrgJw;
  };
  hermes-qdrant-memory = final.callPackage ../packages/hermes-qdrant-memory {
    inherit hermesAgentPackage;
  };
}
