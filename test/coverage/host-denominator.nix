let
  registry = import ../../config/hosts/registry.nix;
in
{
  rows = builtins.map (
    id:
    let
      row = registry.hosts.${id};
      grouped = row ? sharedHome;
    in
    {
      inherit id grouped;
      inherit (row) system activation;
      members = if grouped then row.sharedHome.members else [ id ];
    }
  ) (builtins.attrNames registry.hosts);
}
