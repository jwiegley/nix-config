{
  config,
  lib,
  ...
}:

let
  cfg = config.johnw.omlxProxy;
  ipv4Octet = "(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])";
  canonicalIpv4 = "${ipv4Octet}(\\.${ipv4Octet}){3}";
  listenIsExplicit =
    cfg.listenAddress != "0.0.0.0" && builtins.match canonicalIpv4 cfg.listenAddress != null;
  sourcesAreRestricted =
    cfg.allowedSources != [ ]
    && builtins.all (
      source: source != "all" && builtins.match ".*/0+" source == null
    ) cfg.allowedSources;
in
{
  options.johnw.omlxProxy = {
    enable = lib.mkEnableOption "remote oMLX access through the TLS gateway";

    listenAddress = lib.mkOption {
      type = lib.types.strMatching "[0-9.]+";
      default = "127.0.0.1";
      example = "192.168.1.4";
      description = "Exact interface address used when the oMLX route is exposed.";
    };

    allowedSources = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9.:/-]+");
      default = [ ];
      example = [ "192.168.1.5/32" ];
      description = "Client addresses or CIDR ranges permitted to use the oMLX route.";
    };

    authBasicPasswordFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/[A-Za-z0-9._/+@%=-]+");
      default = null;
      example = "/Users/johnw/.config/omlx/proxy.htpasswd";
      description = ''
        Mutable htpasswd file for the oMLX route. The launch agent requires a
        regular, owner-only file before starting nginx.
      '';
    };
  };

  config.assertions = [
    {
      assertion = !cfg.enable || listenIsExplicit;
      message = "oMLX proxy exposure requires an explicit non-wildcard listen address";
    }
    {
      assertion = !cfg.enable || sourcesAreRestricted;
      message = "oMLX proxy exposure requires a non-empty, restricted source allowlist";
    }
    {
      assertion = !cfg.enable || cfg.authBasicPasswordFile != null;
      message = "oMLX proxy exposure requires a protected Basic-auth password file";
    }
  ];
}
