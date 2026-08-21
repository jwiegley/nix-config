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
  validIpv6Singleton =
    source:
    let
      address = lib.removeSuffix "/128" source;
      compressionParts = lib.splitString "::" address;
      fields = lib.filter (field: field != "") (lib.splitString ":" address);
      hasCompression = builtins.length compressionParts == 2;
    in
    lib.hasSuffix "/128" source
    && address != ""
    && lib.hasInfix ":" address
    && !lib.hasInfix ":::" address
    && builtins.length compressionParts <= 2
    && builtins.all (field: builtins.match "[0-9A-Fa-f]{1,4}" field != null) fields
    && (if hasCompression then builtins.length fields < 8 else builtins.length fields == 8);
  singletonSource =
    source: builtins.match "${canonicalIpv4}/32" source != null || validIpv6Singleton source;
  sourcesAreRestricted = cfg.allowedSources != [ ] && builtins.all singletonSource cfg.allowedSources;
  explicitPath = path: builtins.match "/[A-Za-z0-9._+@%=-]+(/[A-Za-z0-9._+@%=-]+)*" path != null;
  explicitHostPath =
    path:
    let
      components = lib.drop 1 (lib.splitString "/" path);
    in
    explicitPath path && builtins.all (component: component != "." && component != "..") components;
  certificateFilesAreExplicit =
    explicitPath cfg.certificateFile && explicitHostPath cfg.certificateKeyFile;
  privateKeyIsHostLocal =
    explicitHostPath cfg.certificateKeyFile
    && builtins.all (prefix: !lib.hasPrefix prefix cfg.certificateKeyFile) [
      "/nix/store/"
      "/private/tmp/"
      "/tmp/"
      "/var/tmp/"
    ];
  legacyGatewayTrustIsExplicit = !cfg.legacyGatewayEnable || explicitPath cfg.trustedCaFile;
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
      description = "Singleton IPv4 /32 or IPv6 /128 peers permitted to use the oMLX route.";
    };

    legacyGatewayEnable = lib.mkEnableOption "the pre-existing non-oMLX fallback gateway";

    certificateFile = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Absolute path to this host's public TLS certificate.";
    };

    certificateKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Absolute path to this host's private TLS key.";
    };

    trustedCaFile = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Absolute path to the CA used for the gateway's upstream TLS route.";
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
      assertion = !cfg.enable || certificateFilesAreExplicit;
      message = "oMLX proxy exposure requires explicit absolute certificate and key paths";
    }
    {
      assertion = !cfg.enable || privateKeyIsHostLocal;
      message = "oMLX proxy exposure requires a host-local private key path";
    }
    {
      assertion = !cfg.enable || legacyGatewayTrustIsExplicit;
      message = "oMLX legacy gateway exposure requires an explicit absolute trust path";
    }
  ];
}
