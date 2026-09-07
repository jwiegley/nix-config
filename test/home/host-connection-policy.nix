{
  lib,
  pkgs,
  homeManagerLib,
}:

let
  source = builtins.readFile ../../config/hosts.nix;
  baseline = import ../../config/hosts.nix;
  replaceOnce =
    text: edit:
    assert builtins.length (lib.splitString (builtins.head edit) text) == 2;
    lib.replaceStrings [ (builtins.head edit) ] [ (builtins.elemAt edit 1) ] text;
  edits = [
    [
      "hostName = ${builtins.toJSON baseline.hosts.hera.hostName};"
      ''hostName = "probe-hera";''
    ]
    [
      "personal = ${builtins.toJSON baseline.usernames.personal};"
      ''personal = "probeuser";''
    ]
    [
      (builtins.toJSON baseline.hosts.hera.ipv4.lan)
      ''"198.51.100.28"''
    ]
    [
      (builtins.toJSON baseline.hosts.clio.ipv4.lan)
      ''"198.51.100.29"''
    ]
    [
      (builtins.toJSON baseline.hosts.clio.ipv4.wireguard1)
      ''"198.51.100.30"''
    ]
    [
      (builtins.toJSON baseline.hosts.vulcan.ipv4.wifi)
      ''"198.51.100.40"''
    ]
    [
      "system = ${builtins.toJSON baseline.hosts.vulcan.system};"
      ''system = "x86_64-linux";''
    ]
    [
      "maxJobs = ${toString baseline.builders.hera.maxJobs};"
      "maxJobs = 3;"
    ]
    [
      "port = ${toString baseline.inferenceServices.omlx.port};"
      "port = 8999;"
    ]
    [
      "gatewayPort = ${toString baseline.inferenceServices.omlx.gatewayPort};"
      "gatewayPort = 9443;"
    ]
    [
      "llama-swap.port = ${toString baseline.inferenceServices.llama-swap.port};"
      "llama-swap.port = 8888;"
    ]
    [
      "domain = lanDomain;"
      ''domain = "example.invalid";''
    ]
    [
      "hostId = ${builtins.toJSON baseline.hosts.vulcan.hostId};"
      ''hostId = "0123abcd";''
    ]
  ];
  changed = import (
    builtins.toFile "changed-host-registry.nix" (lib.foldl' replaceOnce source edits)
  );
  invalidHostId = import (
    builtins.toFile "invalid-host-id.nix" (
      replaceOnce source [
        "hostId = ${builtins.toJSON baseline.hosts.vulcan.hostId};"
        ''hostId = "invalid";''
      ]
    )
  );
  sharedChanged = import (
    builtins.toFile "changed-shared-hosts.nix" (
      lib.foldl' replaceOnce source [
        [
          "sharedWork = ${builtins.toJSON baseline.usernames.sharedWork};"
          ''sharedWork = "probe.shared";''
        ]
        [
          "andoria = rec {\n      system = ${builtins.toJSON baseline.hosts.andoria.system};"
          "andoria = rec {\n      system = \"aarch64-linux\";"
        ]
        [
          "dnsName = ${builtins.toJSON baseline.hosts.andoria-08.dnsName};"
          ''dnsName = "builder.example.invalid";''
        ]
        [
          "sshUser = ${builtins.toJSON baseline.hosts.git-ai.sshUser};"
          ''sshUser = "probe-bootstrap";''
        ]
      ]
    )
  );
  invalidMember = import (
    builtins.toFile "invalid-shared-member.nix" (
      replaceOnce source [
        "members = [\n"
        "members = [\n      \"missing-shared-host\"\n"
      ]
    )
  );
  invalidAddress = import (
    builtins.toFile "invalid-host-address.nix" (
      replaceOnce source [
        (builtins.toJSON baseline.hosts.hera.ipv4.lan)
        ''"999.1.2.3"''
      ]
    )
  );
  invalidBuilder = import (
    builtins.toFile "invalid-host-builder.nix" (
      replaceOnce source [
        "builderPools = {\n    hera = [\n      \"vulcan\""
        "builderPools = {\n    hera = [\n      \"missing-builder\""
      ]
    )
  );
  rejects = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
  hmLib = lib // {
    inherit (homeManagerLib) hm;
  };
  withoutRouting = import (
    builtins.toFile "host-without-routing.nix" (
      replaceOnce source [
        ''roles = [ "agent-cat-routing" ];''
        "roles = [ ];"
      ]
    )
  );
  routingFilesFor =
    hostRegistry: homeClass:
    let
      fixturePkgs = pkgs // {
        agent-resources = "/fixture-resources";
        pi-gallery = {
          outPath = "/fixture-gallery";
          packages = lib.genAttrs [
            "pi-loop"
            "pi-gpt-fast-mode"
            "pi-provider-llama-swap"
            "pi-provider-omlx"
          ] (_: "/fixture-gallery-package");
        };
      };
    in
    (import ../../config/ai.nix {
      inherit hostRegistry;
      lib = hmLib;
      pkgs = fixturePkgs;
      hostname = homeClass;
      nixManagedAiHomeClass = homeClass;
      inputs.nix-config-ai.packages.${pkgs.stdenv.hostPlatform.system} = {
        inherit (fixturePkgs) agent-resources pi-gallery;
        pi-flag = "/fixture-flag";
        codex.unwrappedPackage = {
          outPath = "/fixture-codex";
          src = ../ai/fixtures/model-policy-codex;
        };
      };
      config = {
        home.homeDirectory = "/fixture-home";
        xdg.configHome = "/fixture-home/.config";
        programs.password-store.settings.PASSWORD_STORE_DIR = "/fixture-pass";
        programs.gpg.homedir = "/fixture-gpg";
      };
    }).home.file;
  sshFor =
    registry: modern:
    (import ../../config/ssh.nix {
      lib = hmLib;
      pkgs = {
        bash = "/fixture-bash";
        my-scripts = "/fixture-scripts";
      };
      hostname = "clio";
      hostRegistry = registry;
      vars = {
        isDarwin = true;
        identityDir = "/fixture-identity";
      };
      options.programs.ssh = lib.optionalAttrs modern { settings = { }; };
      config = {
        home.homeDirectory = "/fixture-home";
        xdg.configHome = "/fixture-config";
        johnw.host = registry.capabilitiesFor { hostname = "clio"; };
      };
    }).programs.ssh;
  gatewayFor =
    registry: hostname:
    (import ../../config/darwin.nix {
      inherit lib hostname;
      pkgs = { };
      config = { };
      inputs = { };
      hostRegistry = registry;
      vulcan-crt = "/fixture-public-ca";
    }).johnw.omlxProxy.content;
  typedFor =
    registry:
    lib.evalModules {
      modules = [
        ../../config/host-options.nix
        "${pkgs.path}/nixos/modules/misc/assertions.nix"
      ];
      specialArgs = {
        hostRegistry = registry;
        hostname = "hera";
      };
    };
  check =
    registry:
    let
      modern = (sshFor registry true).settings;
      legacy = (sshFor registry false).matchBlocks;
      hera = gatewayFor registry "hera";
      clio = gatewayFor registry "clio";
      typed = (typedFor registry).config;
      inherit (registry) hosts inferenceServices;
      catalog = import ../../config/ai/catalog.nix {
        inherit lib;
        hostRegistry = registry;
        resources = "/fixture-resources";
      };
      agents =
        (import ../../config/launchd.nix {
          inherit lib;
          hostname = "hera";
          hostRegistry = registry;
          pkgs = {
            omlx = "/fixture-omlx";
            llama-swap = "/fixture-llama-swap";
            agent-resources = "/fixture-resources";
          };
          config.johnw = {
            host = registry.capabilitiesFor { hostname = "hera"; };
            omlxProxy.enable = false;
          };
        }).launchd.user.agents;
    in
    assert builtins.all (item: item.assertion) typed.assertions;
    assert typed.johnw.hostRegistry.hera.ipv4 == hosts.hera.ipv4;
    assert
      catalog.piModelDiscoveryEndpoints.omlx-hera.baseUrl
      == "https://${hosts.hera.dnsName}:${toString inferenceServices.omlx.gatewayPort}/v1";
    assert
      catalog.localModelEndpointsByHost.hera.omlx
      == "http://localhost:${toString inferenceServices.omlx.port}/v1";
    assert
      catalog.localModelEndpointsByHost.clio.llama-swap
      == "http://localhost:${toString inferenceServices.llama-swap.port}/v1";
    assert lib.hasInfix "--port ${toString inferenceServices.omlx.port}" agents.omlx.script;
    assert lib.hasInfix (lib.escapeShellArg "${hosts.hera.homeDirectory}/.config/omlx/.omlx")
      agents.omlx.script;
    assert lib.hasInfix "127.0.0.1:${toString inferenceServices.llama-swap.port}"
      agents.llama-swap.script;
    assert modern.hera.HostName == hosts.hera.dnsName;
    assert legacy.hera.extraOptions.HostName == hosts.hera.dnsName;
    assert modern.vulcan.HostName == hosts.vulcan.ipv4.lan;
    assert modern.gitea.HostName == hosts.vulcan.ipv4.lan;
    assert modern."srp vps".User == hosts.vps.username;
    assert modern."srp vps".HostName == hosts.vps.dnsName;
    assert modern.positron.ProxyJump == "${hosts.hera.username}@hera";
    assert modern.vulcan_wifi.data.HostName == hosts.vulcan.ipv4.wifi;
    assert lib.hasInfix hosts.clio.ipv4.lan modern.vulcan_wifi.data.header;
    assert legacy.vulcan_wifi.before == [ "vulcan" ];
    assert modern."*".StrictHostKeyChecking == "yes";
    assert modern."*".PasswordAuthentication == false;
    assert legacy."*".extraOptions.PasswordAuthentication == "no";
    assert
      hera.listenAddresses == [
        hosts.hera.ipv4.lan
        hosts.hera.ipv4.overlay
      ];
    assert
      clio.listenAddresses == [
        hosts.clio.ipv4.lan
        hosts.clio.ipv4.overlay
      ];
    assert
      clio.allowedSources == map (ip: "${ip}/32") [
        hosts.hera.ipv4.lan
        hosts.hera.ipv4.overlay
      ];
    assert
      hera.allowedSources == map (ip: "${ip}/32") [
        hosts.vulcan.ipv4.lan
        hosts.clio.ipv4.lan
        hosts.clio.ipv4.wifi
        hosts.clio.ipv4.wireguard1
        registry.networkPeers.stuart.ipv4.wireguard2
        hosts.clio.ipv4.overlay
      ];
    assert registry.builders.hera.hostName == hosts.hera.dnsName;
    assert registry.builders.hera.sshUser == hosts.hera.username;
    assert registry.builders.vulcan.system == hosts.vulcan.system;
    assert registry.builders.vulcan.hostName == hosts.vulcan.dnsName;
    assert typed.johnw.hostRegistry.vulcan.hostId == hosts.vulcan.hostId;
    true;
in
assert check baseline;
assert check changed;
assert builtins.hasAttr ".config/agent-cat/routing.yaml" (routingFilesFor baseline "hera");
assert !(builtins.hasAttr ".config/agent-cat/routing.yaml" (routingFilesFor baseline "clio"));
assert !(builtins.hasAttr ".config/agent-cat/routing.yaml" (routingFilesFor withoutRouting "hera"));
assert changed.hosts.clio.dnsName == baseline.hosts.clio.dnsName;
assert changed.hosts.andoria == baseline.hosts.andoria;
assert changed.builders.hera.maxJobs == 3;
assert changed.builderPools == baseline.builderPools;
assert changed.sharedWork == baseline.sharedWork;
assert sharedChanged.sharedWork == baseline.sharedWork;
assert sharedChanged.hosts.hera == baseline.hosts.hera;
assert builtins.all (
  name:
  sharedChanged.hosts.${name}.username == "probe.shared"
  && sharedChanged.hosts.${name}.system == "aarch64-linux"
  && sharedChanged.hosts.${name}.homeDirectory == "/home/probe.shared"
  && !(sharedChanged.hosts.${name} ? hostName)
) baseline.sharedWork.members;
assert sharedChanged.builders.andoria-08.hostName == "builder.example.invalid";
assert sharedChanged.builders.andoria-08.system == "aarch64-linux";
assert sharedChanged.builders.andoria-t2.sshUser == "probe.shared";
assert (sshFor sharedChanged true).settings."pos andoria".HostName == "builder.example.invalid";
assert (sshFor sharedChanged true).settings."gpu gpu-server".User == "probe.shared";
assert (sshFor sharedChanged true).settings.git-ai.User == "probe-bootstrap";
assert
  (typedFor baseline).config.johnw.hostRegistry.git-ai.sshUser == baseline.hosts.git-ai.sshUser;
assert changed.hosts.vulcan.dnsName == "vulcan.example.invalid";
assert changed.hosts.vulcan.hostId == "0123abcd";
assert rejects (typedFor invalidHostId).config.johnw.hostRegistry.vulcan.hostId;
assert rejects invalidMember;
assert rejects invalidAddress;
assert rejects invalidBuilder;
pkgs.runCommand "host-connection-policy" { } ''
  printf '%s\n' 'Host identity/address propagation and boundary checks passed' > "$out"
''
