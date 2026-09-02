{
  config,
  hostname,
  lib,
  pkgs,
  ...
}:

let
  # Syncthing never binds Tailscale. Clio's route-aware launchd bridges below
  # expose its loopback listener either on the home LAN or through SSH over
  # WireGuard; Hera listens only on its home-LAN address.
  nodes = {
    hera = {
      deviceID = "MDOPNSZ-WLGJBFD-4YUV4S3-QEUZGWP-TLIRRVK-ZXFJ7Q2-IJ3FRBO-ZQVRPAD";
      # Clio reaches Hera only through the route-gated WireGuard SSH tunnel.
      # At home Hera initiates the direct LAN connection to Clio instead.
      addresses = [ "tcp://127.0.0.1:22001" ];
      listenAddress = "tcp://192.168.1.3:22000";
      networks = [
        "192.168.1.3/32"
        "127.0.0.1/32"
      ];
    };
    clio = {
      deviceID = "G3JLOH6-Y5SBVLA-RYANNWG-OXRNO6H-V2FDOSJ-NYYCVF2-UHLDQIU-IMV45A3";
      addresses = [ "tcp://clio.lan:22000" ];
      listenAddress = "tcp://127.0.0.1:22000";
      networks = [
        "192.168.1.5/32"
        "192.168.1.3/32"
      ];
    };
    vulcan = {
      deviceID = "IPWC66H-N6RPNOM-HSX6NKH-Y7MEFTP-GNM75K7-5L6BRIW-OILLNGQ-VQK4ZA2";
      addresses = [ "tcp://192.168.1.2:22000" ];
      listenAddress = "tcp://192.168.1.2:22000";
      networks = [ "192.168.1.2/32" ];
    };
  };

  enabled = config.johnw.host.isDarwinWorkstation;
  localNode = nodes.${hostname};
  peerNames =
    if config.johnw.host.isHera then
      [
        "clio"
        "vulcan"
      ]
    else
      [ "hera" ];
  peerNetworks = lib.unique (lib.concatMap (name: nodes.${name}.networks) peerNames);
  peerAutoAcceptFolders = name: config.johnw.host.isClio && name == "hera";

  stateDirectory = "${config.home.homeDirectory}/Library/Application Support/Syncthing";
  logDirectory = "${config.home.homeDirectory}/Library/Logs/Syncthing";
  runtimeDirectory = "${config.home.homeDirectory}/.local/state/syncthing";
  guiSocket = "${runtimeDirectory}/gui.sock";
  documentsDirectory = "${config.home.homeDirectory}/Documents";
  desktopDirectory = "${config.home.homeDirectory}/Desktop";
  defaultFolderPath = "~/doc";
  # 2.1.3 includes the Darwin-relevant fsync and case-filesystem cache
  # optimizations, but this repository's pinned nixpkgs still carries 2.1.2.
  syncthingPackage = pkgs.callPackage ../packages/syncthing-next.nix { };
  regenerableIgnorePatterns = [
    "(?d).direnv"
    "(?d).mypy_cache"
    "(?d).pytest_cache"
    "(?d).ruff_cache"
    "(?d).venv"
    "(?d)__pycache__"
    "(?d)node_modules"
  ];
  defaultIgnorePatterns = [ "(?d).DS_Store" ] ++ regenerableIgnorePatterns;
  defaultFolderPolicy = {
    path = defaultFolderPath;
    fsWatcherEnabled = true;
    fsWatcherDelayS = 1.0;
    fsWatcherTimeoutS = 5.0;
    rescanIntervalS = 3600;
    scanProgressIntervalS = -1;
    maxConcurrentWrites = 4;
    disableFsync = false;
  };
  defaultPolicy = {
    folder = defaultFolderPolicy;
    ignores = defaultIgnorePatterns;
  };
  monitorLibrary = pkgs.writeText "syncthing-monitor.sh" (builtins.readFile ./syncthing-monitor.sh);
  monitorScripts = import ./syncthing-route-monitors.nix {
    inherit monitorLibrary;
    tools = {
      awk = "/usr/bin/awk";
      ifconfig = "/sbin/ifconfig";
      printf = "/usr/bin/printf";
      remoteTrue = "/usr/bin/true";
      route = "/sbin/route";
      sleep = "/bin/sleep";
      socat = lib.getExe pkgs.socat;
      ssh = "/usr/bin/ssh";
    };
  };
  wireGuardTunnel = pkgs.writeShellScript "syncthing-wireguard-tunnel" monitorScripts.wireGuardTunnel;
  homeLanBridge = pkgs.writeShellScript "syncthing-home-lan-bridge" monitorScripts.homeLanBridge;
  managedFolder =
    {
      id,
      label,
      path,
      ignorePatterns,
    }:
    {
      enable = true;
      inherit
        id
        label
        path
        ignorePatterns
        ;
      filesystemType = "basic";
      type = "sendreceive";
      devices = peerNames;

      fsWatcherEnabled = true;
      fsWatcherDelayS = 1.0;
      fsWatcherTimeoutS = 5.0;
      rescanIntervalS = 3600;
      scanProgressIntervalS = -1;
      maxConcurrentWrites = 4;

      versioning = {
        type = "staggered";
        cleanupIntervalS = 3600;
        fsPath = "";
        fsType = "basic";
        params.maxAge = "31536000";
      };

      maxConflicts = 10;
      ignorePerms = false;
      autoNormalize = true;
      syncOwnership = false;
      sendOwnership = false;
      copyOwnershipFromParent = false;
      disableFsync = false;

      syncXattrs = false;
      sendXattrs = false;
    };
  bootstrapProgram = pkgs.writeTextFile {
    name = "syncthing-bootstrap";
    destination = "/bin/syncthing-bootstrap";
    executable = true;
    text = lib.replaceStrings [ "#!/usr/bin/env python3" ] [ "#!${lib.getExe pkgs.python3}" ] (
      builtins.readFile ./syncthing-bootstrap.py
    );
  };
  bootstrapCommand =
    mode:
    import ./syncthing-bootstrap-command.nix {
      inherit
        defaultPolicy
        desktopDirectory
        documentsDirectory
        guiSocket
        lib
        mode
        stateDirectory
        ;
      inherit (localNode) listenAddress;
      localDeviceID = localNode.deviceID;
      peerPolicies = map (name: {
        deviceID = nodes.${name}.deviceID;
        inherit (nodes.${name}) addresses networks;
        autoAcceptFolders = peerAutoAcceptFolders name;
      }) peerNames;
      program = "${bootstrapProgram}/bin/syncthing-bootstrap";
    };
  preflightTools = {
    awk = "/usr/bin/awk";
    cmp = "${pkgs.diffutils}/bin/cmp";
    grep = "/usr/bin/grep";
    id = "/usr/bin/id";
    install = "${pkgs.coreutils}/bin/install";
    kill = "/bin/kill";
    launchctl = "/bin/launchctl";
    mv = "${pkgs.coreutils}/bin/mv";
    pgrep = "/usr/bin/pgrep";
    plutil = "/usr/bin/plutil";
    ps = "/bin/ps";
    rm = "${pkgs.coreutils}/bin/rm";
    sfltool = "/usr/bin/sfltool";
    sleep = "/bin/sleep";
    stat = "/usr/bin/stat";
    syncthing = lib.getExe syncthingPackage;
    tmutil = "/usr/bin/tmutil";
    tr = "/usr/bin/tr";
  };
  preflightScript = import ./syncthing-preflight.nix {
    inherit
      bootstrapCommand
      desktopDirectory
      desktopIgnoreFile
      documentsDirectory
      documentsIgnoreFile
      guiSocket
      lib
      logDirectory
      runtimeDirectory
      stateDirectory
      ;
    localDeviceID = localNode.deviceID;
    tools = preflightTools;
    username = config.home.username;
  };
  documentsIgnoreFile = pkgs.writeText "documents-syncthing-ignore" ''
    ${lib.concatStringsSep "\n" defaultIgnorePatterns}
    /.git
  '';
  desktopIgnoreFile = pkgs.writeText "desktop-syncthing-ignore" ''
    ${lib.concatStringsSep "\n" defaultIgnorePatterns}
  '';
in
{
  assertions = lib.optional enabled {
    assertion = syncthingPackage.version == "2.1.3";
    message = "The managed Documents sync policy must be reviewed for Syncthing ${syncthingPackage.version}";
  };

  services.syncthing = lib.mkIf enabled {
    enable = true;
    package = syncthingPackage;
    cert = null;
    key = null;

    # Syncthing itself retains a private Unix socket. The launchd bridge below
    # deliberately publishes its unauthenticated GUI on IPv4 loopback.
    guiAddress = guiSocket;
    guiCredentials = null;
    extraOptions = [ "--no-port-probing" ];

    # The offline bootstrap owns stale-device removal. The Home Manager live
    # deletion pass would also target Syncthing's required local device entry.
    overrideDevices = false;
    # Explicit folders remain authoritative, while preserving folders that
    # Clio auto-accepts from Hera in the future.
    overrideFolders = false;

    settings = {
      devices = lib.genAttrs peerNames (name: {
        id = nodes.${name}.deviceID;
        inherit (nodes.${name}) addresses;
        allowedNetworks = nodes.${name}.networks;
        autoAcceptFolders = peerAutoAcceptFolders name;
        introducer = false;
        untrusted = false;
        paused = false;
        compression = "metadata";
      });

      folders = {
        documents = managedFolder {
          id = "documents";
          label = "Documents";
          path = documentsDirectory;
          ignorePatterns = defaultIgnorePatterns ++ [ "/.git" ];
        };
        desktop = managedFolder {
          id = "desktop";
          label = "Desktop";
          path = desktopDirectory;
          ignorePatterns = defaultIgnorePatterns;
        };
      };

      # Auto-accepted folders use ~/doc/<remote label or folder ID>. Documents
      # and Desktop follow peerNames: Clio-Hera and Hera-Vulcan, never
      # Clio-Vulcan.
      "defaults/folder" = defaultFolderPolicy;
      "defaults/ignores" = {
        lines = defaultIgnorePatterns;
      };

      options = {
        listenAddresses = [ localNode.listenAddress ];
        alwaysLocalNets = peerNetworks;
        reconnectionIntervalS = 5;
        maxFolderConcurrency = 1;
        # launchd applies disk-only throttling below; avoid an additional CPU
        # niceness penalty inside Syncthing itself.
        setLowPriority = false;

        globalAnnounceEnabled = false;
        globalAnnounceServers = [ ];
        localAnnounceEnabled = false;
        announceLANAddresses = false;
        relaysEnabled = false;
        natEnabled = false;
        stunServers = [ ];

        urAccepted = -1;
        crashReportingEnabled = false;
        autoUpgradeIntervalH = 0;
        startBrowser = false;
      };
    };
  };

  # launchd opens log files before running the managed jobs. The same preflight also
  # validates the mutable identity and hardens config.xml before first start, so
  # the daemon never exposes Syncthing's default discovery/listener policy.
  home.activation.prepareSyncthing = lib.mkIf enabled (
    lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "linkGeneration" ] ''
      if [[ ! -v DRY_RUN ]]; then
        ${preflightScript}

      fi
    ''
  );

  launchd.agents = lib.mkIf enabled (
    {
      syncthing-gui-bridge = {
        enable = true;
        domain = "gui";
        config = {
          ProgramArguments = [
            (lib.getExe pkgs.socat)
            "TCP4-LISTEN:8384,bind=127.0.0.1,reuseaddr,fork"
            "UNIX-CONNECT:${guiSocket}"
          ];
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "${logDirectory}/syncthing-gui-bridge.log";
          StandardErrorPath = "${logDirectory}/syncthing-gui-bridge.log";
        };
      };

      syncthing = {
        domain = lib.mkForce "gui";
        config = {
          KeepAlive = lib.mkForce true;
          RunAtLoad = lib.mkForce true;
          # Interactive removes launchd's implicit CPU limits; LowPriorityIO
          # then applies only the disk policy requested for this daemon.
          ProcessType = lib.mkForce "Interactive";
          LowPriorityIO = true;
        };
      };

      syncthing-init = {
        domain = lib.mkForce "gui";
        config = {
          RunAtLoad = lib.mkForce true;
          KeepAlive = lib.mkForce { SuccessfulExit = false; };
          ThrottleInterval = lib.mkForce 5;
        };
      };
    }
    // lib.optionalAttrs config.johnw.host.isClio {
      syncthing-home-lan-bridge = {
        enable = true;
        domain = "gui";
        config = {
          ProgramArguments = [ "${homeLanBridge}" ];
          RunAtLoad = true;
          StartInterval = 30;
          StandardOutPath = "${logDirectory}/syncthing-home-lan-bridge.log";
          StandardErrorPath = "${logDirectory}/syncthing-home-lan-bridge.log";
        };
      };

      syncthing-wireguard-tunnel = {
        enable = true;
        domain = "gui";
        config = {
          ProgramArguments = [ "${wireGuardTunnel}" ];
          RunAtLoad = true;
          StartInterval = 30;
          StandardOutPath = "${logDirectory}/syncthing-wireguard-tunnel.log";
          StandardErrorPath = "${logDirectory}/syncthing-wireguard-tunnel.log";
        };
      };
    }
  );
}
