# Declarative host, builder, capability, membership, and routing data shared by
# the module schema, package selector, and generated shell projection. Keeping
# this file free of module arguments lets every consumer import the same tables
# and pure capability function.

let
  lanDomain = "lan";
  llmSetup = {
    defaultHost = "hera";
    localHost = "clio";
    validHosts = [
      "hera"
      "clio"
    ];
    omlxApiBase = "http://${hosts.hera.dnsName}:${toString inferenceServices.omlx.port}";
    gptelEndpoints = {
      llamaSwap = "127.0.0.1:${toString inferenceServices.llama-swap.port}";
      omlx = "127.0.0.1:${toString inferenceServices.omlx.port}";
      vibeProxy = "127.0.0.1:${toString inferenceServices.vibe-proxy.port}";
      rinzler = "127.0.0.1:${toString inferenceServices.rinzler.port}";
      rinzlerAndoria = "${hosts.andoria-t2.dnsName}:${toString inferenceServices.rinzler-andoria.port}";
      hermes = "hermes.${hosts.vulcan.dnsName}";
      perplexity = "api.perplexity.ai";
    };
  };
  networkPeers.googleDns.ipv4 = {
    primary = "8.8.8.8";
    secondary = "8.8.4.4";
  };
  networkPeers.cloudflareDns.ipv4 = {
    primary = "1.1.1.1";
    secondary = "1.0.0.1";
  };
  networkPeers.quad9Dns.ipv4 = {
    primary = "9.9.9.9";
    secondary = "149.112.112.112";
  };
  networkPeers.openDns.ipv4 = {
    primary = "208.67.222.222";
    secondary = "208.67.220.220";
  };
  probeHostGroups = {
    local = [
      networkPeers.router.ipv4.lan
      hosts.vulcan.ipv4.lan
      hosts.hera.ipv4.lan
    ];
    dns = [
      networkPeers.googleDns.ipv4.primary
      networkPeers.googleDns.ipv4.secondary
      networkPeers.cloudflareDns.ipv4.primary
      networkPeers.cloudflareDns.ipv4.secondary
      networkPeers.openDns.ipv4.primary
    ];
    backbone = [
      "google.com"
      "cloudflare.com"
      "amazon.com"
      networkPeers.github.dnsName
    ];
    remote = [ ];
  };
  usernames = {
    personal = "johnw";
    sharedWork = "jwiegley";
  };
  personalLinuxIds = {
    uid = 1000;
    gid = 990;
  };
  userAccounts = {
    vulcan = {
      nasimw = rec {
        username = "nasimw";
        uid = 1001;
        gid = 991;
        homeDirectory = "/home/${username}";
      };
      assembly = rec {
        username = "assembly";
        uid = 1011;
        gid = 1011;
        homeDirectory = "/home/${username}";
      };
      bia = rec {
        username = "bia";
        uid = 1012;
        gid = 1012;
        homeDirectory = "/home/${username}";
      };
      rbcca = rec {
        username = "rbcca";
        uid = 1013;
        gid = 1013;
        homeDirectory = "/home/${username}";
      };
    };
    vps.srashidi = rec {
      username = "srashidi";
      uid = 1001;
      gid = 991;
      homeDirectory = "/home/${username}";
    };
  };
  inferenceServices = {
    omlx = {
      port = 8000;
      gatewayPort = 8443;
    };
    llm-proxy.port = 4000;
    llama-swap.port = 8080;
    vibe-proxy.port = 8317;
    rinzler.port = 63495;
    rinzler-andoria.port = 8088;
    ollama.port = 11434;
    mitm-proxy.port = 9999;
  };
  scriptEndpoints = {
    omlxRemote = "https://${hosts.hera.dnsName}:${toString inferenceServices.omlx.gatewayPort}";
    omlxLocal = "http://localhost:${toString inferenceServices.omlx.port}";
    llamaSwap = "http://localhost:${toString inferenceServices.llama-swap.port}";
    vibeProxy = "http://localhost:${toString inferenceServices.vibe-proxy.port}";
    ollama = "http://localhost:${toString inferenceServices.ollama.port}";
    mitmProxy = "http://localhost:${toString inferenceServices.mitm-proxy.port}";
    hfServer = networkPeers.hfModels.ipv4.inference;
    hfApiPort = 8443;
    hfControlPort = 8080;
  };
  networkRanges = {
    lan = "192.168.1.0/24";
    podman = "10.88.0.0/16";
  };
  networkPeers.hermes = {
    ipv4 = {
      bridge = "10.99.1.1";
      guest = "10.99.1.2";
    };
    prefixLength = 30;
  };
  networkPeers.hfModels.ipv4.inference = "192.168.50.5";
  networkPeers.stuart.ipv4.wireguard2 = "10.7.0.5";
  networkPeers.mssql = {
    via = "hera";
    ipv4.ssh = "192.168.64.3";
  };
  networkPeers.deimos = {
    via = "hera";
    ipv4.ssh = "192.168.221.128";
  };
  networkPeers.simon = {
    via = "hera";
    ipv4.ssh = "172.16.194.158";
  };
  networkPeers.minerva.ipv4.ssh = "192.168.199.128";
  networkPeers.neso = {
    via = "clio";
    ipv4.ssh = "192.168.100.130";
  };
  networkPeers.router.ipv4.lan = "192.168.1.1";
  networkPeers.github.dnsName = "github.com";
  networkPeers.workDev.dnsName = "sw-dev-01";
  networkPeers.asus1 = {
    dnsName = "asus-bq16-pro-ap.${lanDomain}";
    sshPort = 2204;
    sshUser = "router";
  };
  networkPeers.asus2 = networkPeers.asus1 // {
    dnsName = "asus-bq16-pro-node.${lanDomain}";
  };
  networkPeers.elpa.dnsName = "elpa.gnu.org";
  networkPeers.savannah = {
    dnsName = "git.sv.gnu.org";
    aliases = [
      "git.savannah.gnu.org"
      networkPeers.savannah.dnsName
      "git.savannah.nongnu.org"
      "git.sv.nongnu.org"
    ];
  };
  networkPeers.fencepost.dnsName = "fencepost.gnu.org";
  networkPeers.haskellMail.dnsName = "mail.haskell.org";
  syncthing = {
    nodes = {
      hera = rec {
        deviceID = "MDOPNSZ-WLGJBFD-4YUV4S3-QEUZGWP-TLIRRVK-ZXFJ7Q2-IJ3FRBO-ZQVRPAD";
        addresses = [
          "tcp://${hosts.hera.ipv4.overlay}:22000"
          "tcp://${hosts.hera.ipv4.lan}:22000"
        ];
        listenAddresses = addresses;
        networks = [
          "${hosts.hera.ipv4.overlay}/32"
          "${hosts.hera.ipv4.lan}/32"
        ];
      };
      clio = rec {
        deviceID = "G3JLOH6-Y5SBVLA-RYANNWG-OXRNO6H-V2FDOSJ-NYYCVF2-UHLDQIU-IMV45A3";
        addresses = [
          "tcp://${hosts.clio.ipv4.overlay}:22000"
          "tcp://${hosts.clio.ipv4.lan}:22000"
        ];
        listenAddresses = addresses;
        networks = [
          "${hosts.clio.ipv4.overlay}/32"
          # Preserve this existing service-specific entry, not the Wi-Fi address.
          "192.163.3.9/32"
          "${hosts.clio.ipv4.wireguard1}/32"
        ];
      };
      vulcan = rec {
        deviceID = "IPWC66H-N6RPNOM-HSX6NKH-Y7MEFTP-GNM75K7-5L6BRIW-OILLNGQ-VQK4ZA2";
        addresses = [ "tcp://${hosts.vulcan.ipv4.lan}:22000" ];
        listenAddresses = addresses;
        networks = [ "${hosts.vulcan.ipv4.lan}/32" ];
      };
    };
    peers.hera = [
      "clio"
      "vulcan"
    ];
    peers.clio = [ "hera" ];
  };
  ipv4Octet = "(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])";
  validIpv4 =
    address:
    builtins.isString address && builtins.match "${ipv4Octet}(\\.${ipv4Octet}){3}" address != null;
  # Membership is an identity fact, not an availability probe. git-ai remains
  # a real member while dormant; activeRolloutMembers is the deliberately
  # smaller operator target set.
  sharedWork = {
    members = [
      "andoria-08"
      "andoria-t2"
      "delphi-3bd4"
      "git-ai"
      "gpu-server"
    ];
    activeRolloutMembers = [
      "andoria-08"
      "andoria-t2"
      "delphi-3bd4"
      "gpu-server"
    ];
    nixDaemonAllowedCpus = "0-7";
  };

  # Builder identity, capacity, and ordered client pools are host facts. Darwin
  # supplies only the local path for each named SSH identity.
  andoriaBuilder = host: {
    hostName = host.dnsName;
    protocol = "ssh-ng";
    inherit (host) system;
    sshUser = host.username;
    sshIdentity = "positron";
    maxJobs = 1;
    speedFactor = 4;
    supportedFeatures = [ "big-parallel" ];
  };
  builders = {
    hera = {
      hostName = hosts.hera.dnsName;
      protocol = "ssh-ng";
      system = hosts.hera.system;
      sshUser = hosts.hera.username;
      sshIdentity = "host";
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUU5Mk1uem14L0NWUzZHaUdiSjF2R0MwU2RmK0Q3L3ZTVS9QTjdmMVkxTVYK";
      maxJobs = 24;
      speedFactor = 4;
    };
    vulcan = {
      hostName = hosts.vulcan.dnsName;
      protocol = "ssh-ng";
      system = hosts.vulcan.system;
      sshUser = hosts.vulcan.username;
      sshIdentity = "host";
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUl0TUQ4ODYveGxlUzRpaE5QL3lwZ1VieSsyUnd6UFNJVm5CL0k1aTNXRW8gcm9vdEBuaXhvcwo=";
      maxJobs = 4;
      speedFactor = 2;
      supportedFeatures = [
        "nixos-test"
        "big-parallel"
        "kvm"
      ];
    };
    andoria-08 = andoriaBuilder hosts.andoria-08 // {
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSVBUazhVay9ucEJZRnB2dURRS1lHNFZmZStPdFAwRDM0RkRlNi9scDdyUnggcm9vdEBwb3NpdHJvbgo=";
    };
    andoria-t2 = andoriaBuilder hosts.andoria-t2 // {
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUwzK28xbWVYQkNZSzhQOTBQL2tIYW4xcnVYMkpEcmZrQUZaUklhcjZrbTIK";
    };
  };

  builderPools = {
    hera = [
      "vulcan"
      "andoria-08"
      "andoria-t2"
    ];
    clio = [
      "hera"
      "vulcan"
      "andoria-08"
      "andoria-t2"
    ];
  };

  # Local resource ceilings are host facts. Shell dispatchers consume this
  # table through the generated routing library rather than naming hosts.
  localBuildLimits = {
    vps = {
      maxJobs = 1;
      cores = 1;
    };
  };

  # Canonical host classes and their shell-facing aliases. The shell library
  # is generated from this table; do not duplicate these names in Bash.
  routing = {
    hera = {
      flakeOutput = "hera";
      exactNames = [ ];
      containsNames = [ "hera" ];
    };
    clio = {
      flakeOutput = "clio";
      exactNames = [ ];
      containsNames = [ "clio" ];
    };
    vulcan = {
      flakeOutput = "vulcan";
      exactNames = [ ];
      containsNames = [ "vulcan" ];
    };
    vps = {
      flakeOutput = "ovh-vps";
      exactNames = [ "ovh-vps" ];
      containsNames = [ "srp-next" ];
    };
    shared-work = {
      flakeOutput = "jwiegley";
      exactNames = sharedWork.members;
      containsNames = [ ];
    };
  };

  # Home classes are logical evaluation identities. Keep their catalog and
  # concrete-registry projections separate: the personal-linux fixture selects
  # VPS AI profiles but must not inherit the VPS host row or server-lean role.
  homeClasses = {
    clio = {
      registryId = "clio";
      catalogHost = "clio";
    };
    hera = {
      registryId = "hera";
      catalogHost = "hera";
    };
    personal-linux = {
      registryId = null;
      catalogHost = "vps";
    };
    shared-work = {
      registryId = "andoria";
      catalogHost = "shared-work";
    };
    vps = {
      registryId = "vps";
      catalogHost = "vps";
    };
    vulcan = {
      registryId = "vulcan";
      catalogHost = "vulcan";
    };
  };

  # Host rows plus one shared-work group row.
  hosts = {
    hera = rec {
      hostName = "hera";
      dnsName = "${hostName}.${lanDomain}";
      mdnsName = "Hera.local";
      system = "aarch64-darwin";
      activation = "darwin";
      username = usernames.personal;
      homeDirectory = "/Users/${username}";
      ipv4 = {
        lan = "192.168.1.3";
        mdns = "192.168.3.6";
        overlay = "10.55.0.1";
      };
      roles = [ "agent-cat-routing" ];
    };
    clio = rec {
      hostName = "clio";
      dnsName = "${hostName}.${lanDomain}";
      system = "aarch64-darwin";
      activation = "darwin";
      username = usernames.personal;
      homeDirectory = "/Users/${username}";
      ipv4 = {
        lan = "192.168.1.39";
        wifi = "192.168.3.9";
        wireguard1 = "10.6.0.2";
        overlay = "10.55.0.2";
      };
      roles = [ ];
    };
    vulcan = rec {
      hostName = "vulcan";
      domain = lanDomain;
      dnsName = "${hostName}.${domain}";
      hostId = "671bf6f5";
      system = "aarch64-linux";
      activation = "nixos-module";
      username = usernames.personal;
      inherit (personalLinuxIds) uid gid;
      homeDirectory = "/home/${username}";
      ipv4 = {
        lan = "192.168.1.2";
        wifi = "192.168.3.16";
        podman = "10.88.0.1";
      };
      roles = [ "server-lean" ];
    };
    vps = rec {
      hostName = "vps";
      dnsName = "vps-b30dd5a8.vps.ovh.ca";
      system = "x86_64-linux";
      activation = "nixos-module";
      username = usernames.personal;
      inherit (personalLinuxIds) uid gid;
      homeDirectory = "/home/${username}";
      roles = [ "server-lean" ];
    };

    # Group the shared-work membership under one profile identity.
    andoria = rec {
      system = "x86_64-linux";
      activation = "home-standalone";
      username = usernames.sharedWork;
      homeDirectory = "/home/${username}";
      roles = [ ];
    };
    andoria-08 = hosts.andoria // {
      dnsName = "andoria-08";
    };
    andoria-t2 = hosts.andoria // {
      dnsName = "andoria-t2";
    };
    delphi-3bd4 = hosts.andoria // {
      dnsName = "delphi-3bd4";
    };
    gpu-server = hosts.andoria // {
      dnsName = "gpu-server";
    };
    git-ai = hosts.andoria // {
      dnsName = "ec2-3-134-98-233.us-east-2.compute.amazonaws.com";
      sshUser = "ubuntu";
    };
  };

  homeClassNames = builtins.attrNames homeClasses;
  homeClassContractFor =
    name:
    let
      row = homeClasses.${name} or null;
    in
    {
      inherit row;
      assertion = row != null;
      message = "set nixManagedAiHomeClass to one of ${builtins.concatStringsSep ", " homeClassNames}";
    };

  resolveFor =
    {
      hostname,
      homeClass ? null,
    }:
    let
      homeClassRow = if homeClass == null then null else (homeClassContractFor homeClass).row;
      registryId = if homeClassRow == null then hostname else homeClassRow.registryId;
    in
    {
      inherit homeClassRow registryId;
      registryRow = if registryId == null then null else hosts.${registryId} or null;
    };

in
assert builtins.all (
  service:
  builtins.all (port: builtins.isInt port && port > 0 && port <= 65535) (builtins.attrValues service)
) (builtins.attrValues inferenceServices);
assert builtins.all (row: builtins.all validIpv4 (builtins.attrValues (row.ipv4 or { }))) (
  builtins.attrValues hosts ++ builtins.attrValues networkPeers
);
assert builtins.all (row: row.registryId == null || builtins.hasAttr row.registryId hosts) (
  builtins.attrValues homeClasses
);
assert builtins.all (host: builtins.hasAttr host hosts) sharedWork.members;
assert builtins.all (host: builtins.elem host sharedWork.members) sharedWork.activeRolloutMembers;
assert builtins.all (pool: builtins.all (builder: builtins.hasAttr builder builders) pool) (
  builtins.attrValues builderPools
);
assert builtins.all (name: builtins.hasAttr name routing) (builtins.attrNames localBuildLimits);
assert builtins.all (
  limits:
  builtins.isInt limits.maxJobs
  && limits.maxJobs > 0
  && builtins.isInt limits.cores
  && limits.cores > 0
) (builtins.attrValues localBuildLimits);
{
  inherit
    builderPools
    builders
    homeClasses
    homeClassContractFor
    hosts
    inferenceServices
    localBuildLimits
    networkPeers
    usernames
    userAccounts
    routing
    resolveFor
    sharedWork
    syncthing
    llmSetup
    scriptEndpoints
    probeHostGroups
    networkRanges
    ;

  # Pure, total capability derivation. Unknown names never throw: concrete-host
  # flags remain false, while CI-fixture and shared-work flags follow their
  # explicit inputs.
  capabilitiesFor =
    {
      hostname,
      homeClass ? null,
    }:
    let
      resolved = resolveFor { inherit hostname homeClass; };
      id = resolved.registryId;
    in
    {
      isHera = id == "hera";
      isClio = id == "clio";
      isVulcan = id == "vulcan";

      # The two Darwin GUI workstations (hera OR clio).
      isDarwinWorkstation = id == "hera" || id == "clio";

      # Resolve the shared-work group from either its explicit home class or a
      # physical member hostname.
      isSharedWork = id == "andoria" || builtins.elem hostname sharedWork.members;

      # The synthetic CI evaluation fixtures pin the name to "linux".
      isCiFixture = hostname == "linux";
    };
}
