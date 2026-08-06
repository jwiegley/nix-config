{
  config,
  hostname,
  lib,
  pkgs,
  ...
}:

let
  nodes = {
    hera = {
      deviceID = "MDOPNSZ-WLGJBFD-4YUV4S3-QEUZGWP-TLIRRVK-ZXFJ7Q2-IJ3FRBO-ZQVRPAD";
      endpoint = "tcp://100.120.206.121:22000";
      network = "100.120.206.121/32";
    };
    clio = {
      deviceID = "G3JLOH6-Y5SBVLA-RYANNWG-OXRNO6H-V2FDOSJ-NYYCVF2-UHLDQIU-IMV45A3";
      endpoint = "tcp://100.113.64.49:22000";
      network = "100.113.64.49/32";
    };
  };

  enabled = config.johnw.host.isDarwinWorkstation;
  localNode = nodes.${hostname};
  peerName = if config.johnw.host.isHera then "clio" else "hera";
  peerNode = nodes.${peerName};

  stateDirectory = "${config.home.homeDirectory}/Library/Application Support/Syncthing";
  logDirectory = "${config.home.homeDirectory}/Library/Logs/Syncthing";
  runtimeDirectory = "${config.home.homeDirectory}/.local/state/syncthing";
  guiSocket = "${runtimeDirectory}/gui.sock";
  vaultDirectory = "${config.home.homeDirectory}/.obsidian";
  bootstrapProgram = pkgs.writeScript "syncthing-bootstrap" (
    lib.replaceStrings [ "#!/usr/bin/env python3" ] [ "#!${lib.getExe pkgs.python3}" ] (
      builtins.readFile ./syncthing-bootstrap.py
    )
  );
  bootstrapCommand =
    mode:
    lib.escapeShellArgs [
      "${bootstrapProgram}"
      mode
      "--config"
      "${stateDirectory}/config.xml"
      "--local-device-id"
      localNode.deviceID
      "--peer-device-id"
      peerNode.deviceID
      "--peer-address"
      peerNode.endpoint
      "--listen-address"
      localNode.endpoint
      "--peer-network"
      peerNode.network
      "--gui-socket"
      guiSocket
      "--vault"
      vaultDirectory
    ];
  ignoreFile = pkgs.writeText "obsidian-syncthing-ignore" ''
    (?d).DS_Store
  '';
in
{
  assertions = lib.optional enabled {
    assertion = pkgs.syncthing.version == "2.1.2";
    message = "The managed Obsidian sync policy must be reviewed for Syncthing ${pkgs.syncthing.version}";
  };

  services.syncthing = lib.mkIf enabled {
    enable = true;
    package = pkgs.syncthing;
    cert = null;
    key = null;

    # A private Unix socket avoids both a loopback-wide unauthenticated GUI and
    # Home Manager's password-through-jq-argv credential path.
    guiAddress = guiSocket;
    guiCredentials = null;
    extraOptions = [ "--no-port-probing" ];

    overrideDevices = true;
    overrideFolders = true;

    settings = {
      devices.${peerName} = {
        id = peerNode.deviceID;
        addresses = [ peerNode.endpoint ];
        allowedNetworks = [ peerNode.network ];
        autoAcceptFolders = false;
        introducer = false;
        untrusted = false;
        paused = false;
        compression = "metadata";
      };

      folders.obsidian = {
        enable = true;
        id = "obsidian";
        label = "Obsidian";
        path = "${config.home.homeDirectory}/.obsidian";
        filesystemType = "basic";
        type = "sendreceive";
        devices = [ peerName ];

        fsWatcherEnabled = true;
        fsWatcherDelayS = 1.0;
        fsWatcherTimeoutS = 0.0;
        rescanIntervalS = 300;

        versioning = {
          type = "staggered";
          cleanupIntervalS = 3600;
          fsPath = "";
          fsType = "basic";
          params.maxAge = "31536000";
        };

        ignorePatterns = [ "(?d).DS_Store" ];
        maxConflicts = 10;
        ignorePerms = false;
        autoNormalize = true;
        syncOwnership = false;
        sendOwnership = false;
        copyOwnershipFromParent = false;
        disableFsync = false;

        syncXattrs = true;
        sendXattrs = true;
        xattrFilter = {
          entries = [ ];
          maxSingleEntrySize = 16777216;
          maxTotalSize = 67108864;
        };
      };

      options = {
        listenAddresses = [ localNode.endpoint ];
        alwaysLocalNets = [ peerNode.network ];
        reconnectionIntervalS = 5;

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

  # launchd opens log files before running either job. The same preflight also
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
          [[ -d "$path" && ! -L "$path" ]] || syncthing_fail "required private directory is missing or unsafe"
          [[ "$(/usr/bin/stat -f '%Su' "$path")" == ${lib.escapeShellArg config.home.username} ]] \
            || syncthing_fail "private directory has the wrong owner"
          [[ "$(/usr/bin/stat -f '%Lp' "$path")" == "$expected_mode" ]] \
            || syncthing_fail "private directory has the wrong mode"
        }
        syncthing_require_file() {
          local path="$1"
          [[ -f "$path" && ! -L "$path" ]] || syncthing_fail "required private file is missing or unsafe"
          [[ "$(/usr/bin/stat -f '%Su' "$path")" == ${lib.escapeShellArg config.home.username} ]] \
            || syncthing_fail "private file has the wrong owner"
          [[ "$(/usr/bin/stat -f '%Lp' "$path")" == "600" ]] \
            || syncthing_fail "private file has the wrong mode"
        }

        ${pkgs.coreutils}/bin/install -d -m 0700 \
          ${lib.escapeShellArg logDirectory} \
          ${lib.escapeShellArg runtimeDirectory}
        syncthing_require_directory ${lib.escapeShellArg stateDirectory} 700
        syncthing_require_directory ${lib.escapeShellArg logDirectory} 700
        syncthing_require_directory ${lib.escapeShellArg runtimeDirectory} 700
        syncthing_require_directory ${lib.escapeShellArg vaultDirectory} 700
        syncthing_require_file ${lib.escapeShellArg "${stateDirectory}/cert.pem"}
        syncthing_require_file ${lib.escapeShellArg "${stateDirectory}/key.pem"}
        syncthing_require_file ${lib.escapeShellArg "${stateDirectory}/config.xml"}

        actual_device_id="$(${lib.getExe pkgs.syncthing} device-id --home ${lib.escapeShellArg stateDirectory} 2>/dev/null)" \
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

        if [[ -L ${lib.escapeShellArg "${vaultDirectory}/.stignore"} ]] \
          || { [[ -e ${lib.escapeShellArg "${vaultDirectory}/.stignore"} ]] \
            && [[ ! -f ${lib.escapeShellArg "${vaultDirectory}/.stignore"} ]]; }; then
          syncthing_fail ".stignore is not a safe regular file"
        fi
        if ! ${pkgs.diffutils}/bin/cmp -s ${ignoreFile} ${lib.escapeShellArg "${vaultDirectory}/.stignore"}; then
          (
            set -e
            ignore_tmp=${lib.escapeShellArg "${vaultDirectory}/.stignore.tmp"}.$$
            trap '${pkgs.coreutils}/bin/rm -f "$ignore_tmp"' EXIT
            ${pkgs.coreutils}/bin/install -m 0600 ${ignoreFile} "$ignore_tmp"
            ${pkgs.coreutils}/bin/mv -f "$ignore_tmp" ${lib.escapeShellArg "${vaultDirectory}/.stignore"}
          ) || syncthing_fail "could not install the managed .stignore"
        fi

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

  launchd.agents = lib.mkIf enabled {
    syncthing = {
      domain = lib.mkForce "gui";
      config = {
        KeepAlive = lib.mkForce true;
        RunAtLoad = lib.mkForce true;
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
  };
}
