let
  byHost = {
    clio = {
      environment = "OMLX_CLIO_API_KEY";
      keychain = {
        account = "johnw";
        service = "nix-config.omlx-clio-client";
      };
    };
    hera = {
      environment = "OMLX_HERA_API_KEY";
      keychain = {
        account = "johnw";
        service = "nix-config.omlx-hera-client";
      };
    };
  };
in
{
  inherit byHost;
  keychainByEnvironment = builtins.listToAttrs (
    map (host: {
      name = byHost.${host}.environment;
      value = byHost.${host}.keychain;
    }) (builtins.attrNames byHost)
  );
}
