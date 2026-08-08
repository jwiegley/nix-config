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
      listenAddress = "tcp://192.168.1.4:22000";
      networks = [
        "192.168.1.4/32"
        "127.0.0.1/32"
      ];
    };
    clio = {
      deviceID = "G3JLOH6-Y5SBVLA-RYANNWG-OXRNO6H-V2FDOSJ-NYYCVF2-UHLDQIU-IMV45A3";
      addresses = [ "tcp://clio.local:22000" ];
      listenAddress = "tcp://127.0.0.1:22000";
      networks = [
        "192.168.1.5/32"
        "192.168.1.4/32"
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
  syncthingPackage = pkgs.syncthing.overrideAttrs (
    _finalAttrs: _previousAttrs: {
      version = "2.1.3";
      src = pkgs.fetchFromGitHub {
        owner = "syncthing";
        repo = "syncthing";
        tag = "v2.1.3";
        hash = "sha256-uTjmOAjis2eBm2SnZbyvDDiQXKN8De+DhjNHbFLLbn0=";
      };
      vendorHash = "sha256-ueUf9YEa5z7mG6MofIJ3Xco+PxVPi/85Rdi+1aean6c=";
    }
  );
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
  wireGuardTunnel = pkgs.writeShellScript "syncthing-wireguard-tunnel" ''
    set -euo pipefail

    wireguard_route_active() {
      route_interface="$(
        /sbin/route -n get 192.168.1.4 2>/dev/null \
          | /usr/bin/awk '/^[[:space:]]*interface: / { print $2; exit }'
      )" || return 1
      [ -n "$route_interface" ] \
        && /sbin/ifconfig "$route_interface" 2>/dev/null \
          | /usr/bin/awk '$1 == "inet" && $2 == "10.6.0.2" { found = 1 } END { exit !found }'
    }
    wireguard_route_active || exit 0

    /usr/bin/ssh \
      -N -T \
      -B "$route_interface" \
      -b 10.6.0.2 \
      -o BatchMode=yes \
      -o ConnectTimeout=10 \
      -o ConnectionAttempts=1 \
      -o ControlMaster=no \
      -o ControlPath=none \
      -o ExitOnForwardFailure=yes \
      -o ForwardAgent=no \
      -o HostName=192.168.1.4 \
      -o PermitLocalCommand=no \
      -o ProxyCommand=none \
      -o ProxyJump=none \
      -o ServerAliveCountMax=3 \
      -o ServerAliveInterval=15 \
      -o StrictHostKeyChecking=yes \
      -L 127.0.0.1:22001:192.168.1.4:22000 \
      hera &
    child_pid=$!
    cleanup() {
      kill -TERM "$child_pid" 2>/dev/null || true
      wait "$child_pid" 2>/dev/null || true
    }
    trap cleanup EXIT HUP INT TERM
    while kill -0 "$child_pid" 2>/dev/null; do
      /bin/sleep 30
      wireguard_route_active || exit 0
    done
    child_status=0
    wait "$child_pid" || child_status=$?
    trap - EXIT HUP INT TERM
    exit "$child_status"
  '';
  homeLanBridge = pkgs.writeShellScript "syncthing-home-lan-bridge" ''
    set -euo pipefail

    home_route_active() {
      route_interface="$(
        /sbin/route -n get 192.168.1.4 2>/dev/null \
          | /usr/bin/awk '/^[[:space:]]*interface: / { print $2; exit }'
      )" || return 1
      case "$route_interface" in
        "" | utun*) return 1 ;;
      esac
      /sbin/ifconfig "$route_interface" 2>/dev/null \
        | /usr/bin/awk '$1 == "inet" && $2 == "192.168.1.5" { found = 1 } END { exit !found }'
    }
    home_route_active || exit 0

    /usr/bin/ssh \
      -T \
      -b 192.168.1.5 \
      -o BatchMode=yes \
      -o ClearAllForwardings=yes \
      -o ConnectTimeout=3 \
      -o ConnectionAttempts=1 \
      -o ControlMaster=no \
      -o ControlPath=none \
      -o ForwardAgent=no \
      -o HostName=192.168.1.4 \
      -o PermitLocalCommand=no \
      -o ProxyCommand=none \
      -o ProxyJump=none \
      -o StrictHostKeyChecking=yes \
      hera /usr/bin/true </dev/null

    ${lib.getExe pkgs.socat} \
      "TCP4-LISTEN:22000,bind=192.168.1.5,range=192.168.1.4/32,reuseaddr" \
      "TCP4:127.0.0.1:22000" &
    child_pid=$!
    cleanup() {
      kill -TERM "$child_pid" 2>/dev/null || true
      wait "$child_pid" 2>/dev/null || true
    }
    trap cleanup EXIT HUP INT TERM
    while kill -0 "$child_pid" 2>/dev/null; do
      /bin/sleep 30
      home_route_active || exit 0
    done
    child_status=0
    wait "$child_pid" || child_status=$?
    trap - EXIT HUP INT TERM
    exit "$child_status"
  '';
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
  bootstrapProgram = pkgs.writeScript "syncthing-bootstrap" (
    lib.replaceStrings [ "#!/usr/bin/env python3" ] [ "#!${lib.getExe pkgs.python3}" ] (
      builtins.readFile ./syncthing-bootstrap.py
    )
  );
  bootstrapCommand =
    mode:
    lib.escapeShellArgs (
      [
        "${bootstrapProgram}"
        mode
        "--config"
        "${stateDirectory}/config.xml"
        "--local-device-id"
        localNode.deviceID
        "--listen-address"
        localNode.listenAddress
      ]
      ++ lib.concatMap (name: [
        "--peer-policy"
        (builtins.toJSON {
          deviceID = nodes.${name}.deviceID;
          inherit (nodes.${name}) addresses networks;
          autoAcceptFolders = peerAutoAcceptFolders name;
        })
      ]) peerNames
      ++ [
        "--gui-socket"
        guiSocket
        "--default-policy"
        (builtins.toJSON defaultPolicy)
        "--documents"
        documentsDirectory
        "--desktop"
        desktopDirectory
      ]
    );
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
        syncthing_fail() {
          echo "syncthing preflight: $1" >&2
          exit 1
        }
        syncthing_require_directory() {
          local path="$1" expected_mode="$2"
          [[ -d "$path" && ! -L "$path" ]] \
            || syncthing_fail "required private directory is missing or unsafe: $path"
          [[ "$(/usr/bin/stat -f '%Su' "$path")" == ${lib.escapeShellArg config.home.username} ]] \
            || syncthing_fail "private directory has the wrong owner: $path"
          [[ "$(/usr/bin/stat -f '%Lp' "$path")" == "$expected_mode" ]] \
            || syncthing_fail "private directory has the wrong mode: $path"
        }
        syncthing_require_file() {
          local path="$1"
          [[ -f "$path" && ! -L "$path" ]] \
            || syncthing_fail "required private file is missing or unsafe: $path"
          [[ "$(/usr/bin/stat -f '%Su' "$path")" == ${lib.escapeShellArg config.home.username} ]] \
            || syncthing_fail "private file has the wrong owner: $path"
          [[ "$(/usr/bin/stat -f '%Lp' "$path")" == "600" ]] \
            || syncthing_fail "private file has the wrong mode: $path"
        }

        ${pkgs.coreutils}/bin/install -d -m 0700 \
          ${lib.escapeShellArg logDirectory} \
          ${lib.escapeShellArg runtimeDirectory}
        syncthing_require_directory ${lib.escapeShellArg stateDirectory} 700
        syncthing_require_directory ${lib.escapeShellArg logDirectory} 700
        syncthing_require_directory ${lib.escapeShellArg runtimeDirectory} 700
        syncthing_require_directory ${lib.escapeShellArg documentsDirectory} 700
        syncthing_require_directory ${lib.escapeShellArg desktopDirectory} 700
        syncthing_require_file ${lib.escapeShellArg "${stateDirectory}/cert.pem"}
        syncthing_require_file ${lib.escapeShellArg "${stateDirectory}/key.pem"}
        syncthing_require_file ${lib.escapeShellArg "${stateDirectory}/config.xml"}

        actual_device_id="$(${lib.getExe syncthingPackage} device-id --home ${lib.escapeShellArg stateDirectory} 2>/dev/null)" \
          || syncthing_fail "could not derive the bootstrapped device identity"
        [[ "$actual_device_id" == ${lib.escapeShellArg localNode.deviceID} ]] \
          || syncthing_fail "bootstrapped device identity does not match this host"

        if /usr/bin/pgrep -f '/Applications/Syncthing[.]app/Contents/MacOS/Syncthing' >/dev/null 2>&1; then
          syncthing_fail "Syncthing.app must remain closed while Home Manager owns the daemon"
        fi

        login_items_status=0
        (
          set -e
          login_items=${lib.escapeShellArg "${runtimeDirectory}/login-items"}.$$
          trap '${pkgs.coreutils}/bin/rm -f "$login_items"' EXIT
          ${pkgs.coreutils}/bin/install -m 0600 /dev/null "$login_items" || exit 10
          /usr/bin/sfltool list com.apple.LSSharedFileList.SessionLoginItems >"$login_items" 2>&1 &
          login_items_pid=$!
          login_items_done=0
          for ((attempt = 0; attempt < 50; attempt++)); do
            if ! /bin/kill -0 "$login_items_pid" 2>/dev/null; then
              if wait "$login_items_pid"; then
                login_items_done=1
              fi
              break
            fi
            /bin/sleep 0.1
          done
          if [[ "$login_items_done" == 0 ]]; then
            /bin/kill "$login_items_pid" 2>/dev/null || true
            wait "$login_items_pid" 2>/dev/null || true
            exit 10
          fi
          if /usr/bin/grep -Eiq '(/Applications/Syncthing\.app|com\.github\.xor-gate\.syncthing-macosx)' "$login_items"; then
            exit 20
          fi
        ) || login_items_status=$?
        case "$login_items_status" in
          0) ;;
          20) syncthing_fail "Syncthing.app is still registered as a login item" ;;
          *) syncthing_fail "could not safely inspect legacy login items" ;;
        esac

        daemon_pids=( )
        for ((attempt = 0; attempt < 20; attempt++)); do
          mapfile -t daemon_pids < <(/usr/bin/pgrep -x syncthing 2>/dev/null || true)
          (( ''${#daemon_pids[@]} != 1 )) && break
          /bin/sleep 0.1
        done
        daemon_running=0
        if (( ''${#daemon_pids[@]} > 0 )); then
          managed_pid="$(/bin/launchctl print gui/$(/usr/bin/id -u)/org.nix-community.home.syncthing 2>/dev/null \
            | /usr/bin/awk '/^[[:space:]]*pid = / { print $3; exit }')"
          [[ -n "$managed_pid" && ''${#daemon_pids[@]} == 2 ]] \
            || syncthing_fail "an unmanaged, duplicate, or unhealthy Syncthing instance is running"
          if [[ "''${daemon_pids[0]}" == "$managed_pid" ]]; then
            child_pid="''${daemon_pids[1]}"
          elif [[ "''${daemon_pids[1]}" == "$managed_pid" ]]; then
            child_pid="''${daemon_pids[0]}"
          else
            syncthing_fail "the Syncthing monitor is not owned by the managed launchd job"
          fi
          child_parent="$(/bin/ps -p "$child_pid" -o ppid= | /usr/bin/tr -d ' ')"
          [[ "$child_parent" == "$managed_pid" ]] \
            || syncthing_fail "the second Syncthing process is not the managed monitor child"
          daemon_running=1
        fi

        if [[ -L ${lib.escapeShellArg "${documentsDirectory}/.stignore"} ]] \
          || { [[ -e ${lib.escapeShellArg "${documentsDirectory}/.stignore"} ]] \
            && [[ ! -f ${lib.escapeShellArg "${documentsDirectory}/.stignore"} ]]; }; then
          syncthing_fail "Documents .stignore is not a safe regular file"
        fi
        if ! ${pkgs.diffutils}/bin/cmp -s ${documentsIgnoreFile} ${lib.escapeShellArg "${documentsDirectory}/.stignore"}; then
          (
            set -e
            ignore_tmp=${lib.escapeShellArg "${documentsDirectory}/.stignore.tmp"}.$$
            trap '${pkgs.coreutils}/bin/rm -f "$ignore_tmp"' EXIT
            ${pkgs.coreutils}/bin/install -m 0600 ${documentsIgnoreFile} "$ignore_tmp"
            ${pkgs.coreutils}/bin/mv -f "$ignore_tmp" ${lib.escapeShellArg "${documentsDirectory}/.stignore"}
          ) || syncthing_fail "could not install the managed Documents .stignore"
        fi

        if [[ -L ${lib.escapeShellArg "${desktopDirectory}/.stignore"} ]] \
          || { [[ -e ${lib.escapeShellArg "${desktopDirectory}/.stignore"} ]] \
            && [[ ! -f ${lib.escapeShellArg "${desktopDirectory}/.stignore"} ]]; }; then
          syncthing_fail "Desktop .stignore is not a safe regular file"
        fi
        if ! ${pkgs.diffutils}/bin/cmp -s ${desktopIgnoreFile} ${lib.escapeShellArg "${desktopDirectory}/.stignore"}; then
          (
            set -e
            ignore_tmp=${lib.escapeShellArg "${desktopDirectory}/.stignore.tmp"}.$$
            trap '${pkgs.coreutils}/bin/rm -f "$ignore_tmp"' EXIT
            ${pkgs.coreutils}/bin/install -m 0600 ${desktopIgnoreFile} "$ignore_tmp"
            ${pkgs.coreutils}/bin/mv -f "$ignore_tmp" ${lib.escapeShellArg "${desktopDirectory}/.stignore"}
          ) || syncthing_fail "could not install the managed Desktop .stignore"
        fi

        syncthing_exclude_from_time_machine() {
          local path="$1" excluded
          excluded="$(
            /usr/bin/tmutil isexcluded -X "$path" \
              | /usr/bin/plutil -extract 0.IsExcluded raw -o - -- -
          )" || syncthing_fail "could not inspect Time Machine exclusion"
          if [[ "$excluded" != 1 ]]; then
            /usr/bin/tmutil addexclusion "$path" \
              || syncthing_fail "could not add Time Machine exclusion"
          fi
        }
        syncthing_exclude_from_time_machine ${lib.escapeShellArg documentsDirectory}
        syncthing_exclude_from_time_machine ${lib.escapeShellArg desktopDirectory}

        if [[ -e ${lib.escapeShellArg guiSocket} || -L ${lib.escapeShellArg guiSocket} ]]; then
          [[ -S ${lib.escapeShellArg guiSocket} && ! -L ${lib.escapeShellArg guiSocket} ]] \
            || syncthing_fail "GUI socket path is unsafe"
          if [[ "$daemon_running" == 0 ]]; then
            ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg guiSocket}
          fi
        fi

        if ${bootstrapCommand "--check"}; then
          :
        else
          bootstrap_status=$?
          [[ "$bootstrap_status" == 3 ]] \
            || syncthing_fail "config.xml failed offline policy validation"
          [[ "$daemon_running" == 0 ]] \
            || syncthing_fail "config.xml needs hardening while the managed daemon is running"
          ${bootstrapCommand "--apply"} \
            || syncthing_fail "could not harden config.xml before launch"
          ${bootstrapCommand "--check"} \
            || syncthing_fail "config.xml did not retain the hardened policy"
        fi
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
