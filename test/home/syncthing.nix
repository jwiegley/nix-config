{
  darwinConfigurations,
  homeConfigurations,
  nixosHomeEvaluationFixtures,
  pkgs,
}:

let
  inherit (pkgs) lib;
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
  heraSystem = darwinConfigurations.hera.config;
  clioSystem = darwinConfigurations.clio.config;
  hera = heraSystem.home-manager.users.johnw;
  clio = clioSystem.home-manager.users.johnw;
  managedSyncthing = pkgs.callPackage ../../packages/syncthing-next.nix { };
  expectedNodes = {
    hera = {
      addresses = [ "tcp://127.0.0.1:22001" ];
      listen = "tcp://192.168.1.4:22000";
      networks = [
        "192.168.1.4/32"
        "127.0.0.1/32"
      ];
    };
    clio = {
      addresses = [ "tcp://clio.lan:22000" ];
      listen = "tcp://127.0.0.1:22000";
      networks = [
        "192.168.1.5/32"
        "192.168.1.4/32"
      ];
    };
    vulcan = {
      addresses = [ "tcp://192.168.1.2:22000" ];
      listen = "tcp://192.168.1.2:22000";
      networks = [ "192.168.1.2/32" ];
    };
  };
  topologyFile = pkgs.writeText "syncthing-topology.json" (
    builtins.toJSON {
      hera = {
        id = clio.services.syncthing.settings.devices.hera.id;
        addresses = clio.services.syncthing.settings.devices.hera.addresses;
        listen = builtins.head hera.services.syncthing.settings.options.listenAddresses;
        networks = clio.services.syncthing.settings.devices.hera.allowedNetworks;
      };
      clio = {
        id = hera.services.syncthing.settings.devices.clio.id;
        addresses = hera.services.syncthing.settings.devices.clio.addresses;
        listen = builtins.head clio.services.syncthing.settings.options.listenAddresses;
        networks = hera.services.syncthing.settings.devices.clio.allowedNetworks;
      };
      vulcan = {
        id = hera.services.syncthing.settings.devices.vulcan.id;
        addresses = hera.services.syncthing.settings.devices.vulcan.addresses;
        listen = expectedNodes.vulcan.listen;
        networks = hera.services.syncthing.settings.devices.vulcan.allowedNetworks;
      };
    }
  );
  heraPreflight = pkgs.writeText "syncthing-hera-preflight" hera.home.activation.prepareSyncthing.data;
  clioPreflight = pkgs.writeText "syncthing-clio-preflight" clio.home.activation.prepareSyncthing.data;
  clioHomeLanBridge =
    builtins.head
      clio.launchd.agents."syncthing-home-lan-bridge".config.ProgramArguments;
  clioWireGuardTunnel =
    builtins.head
      clio.launchd.agents."syncthing-wireguard-tunnel".config.ProgramArguments;
  linuxHomes =
    map (fixture: fixture.config) (builtins.attrValues nixosHomeEvaluationFixtures)
    ++ map (configuration: configuration.config) (builtins.attrValues homeConfigurations);
  validDeviceId = id: builtins.match "[A-Z2-7]{7}(-[A-Z2-7]{7}){7}" id != null;
  hasSyncthingApp =
    system:
    lib.any (
      cask: if builtins.isString cask then cask == "syncthing-app" else cask.name == "syncthing-app"
    ) system.homebrew.casks;
  hasDormantSyncthingApp =
    system:
    let
      preferences = system.system.defaults.CustomUserPreferences."com.github.xor-gate.syncthing-macosx";
    in
    !preferences.StartAtLogin
    && !preferences.SUEnableAutomaticChecks
    && !preferences.SUAutomaticallyUpdate;
  ownsMutableState =
    home:
    lib.any (
      path:
      path == "Documents"
      || lib.hasPrefix "Documents/" path
      || path == "Desktop"
      || lib.hasPrefix "Desktop/" path
      || lib.hasPrefix "Library/Application Support/Syncthing/" path
    ) (builtins.attrNames home.home.file);
  validDarwinHome =
    home: localName:
    let
      localPolicy = expectedNodes.${localName};
      peerNames =
        if localName == "clio" then
          [ "hera" ]
        else
          [
            "clio"
            "vulcan"
          ];
      peerNetworks = lib.unique (lib.concatMap (name: expectedNodes.${name}.networks) peerNames);
      service = home.services.syncthing;
      folders = service.settings.folders;
      inherit (folders) desktop documents;
      defaultFolder = service.settings."defaults/folder";
      defaultIgnores = service.settings."defaults/ignores";
      options = service.settings.options;
      localAddress = builtins.head options.listenAddresses;
      agent = home.launchd.agents.syncthing;
      bridgeAgent = home.launchd.agents.syncthing-gui-bridge;
      initAgent = home.launchd.agents.syncthing-init;
      homeLanBridgeAgent = home.launchd.agents."syncthing-home-lan-bridge" or null;
      wireGuardTunnelAgent = home.launchd.agents."syncthing-wireguard-tunnel" or null;
      preflight = home.home.activation.prepareSyncthing;
      syncthingAgents = lib.filterAttrs (name: _: lib.hasInfix "syncthing" name) home.launchd.agents;
      isClio = localName == "clio";
      expectedAgentNames = [
        "syncthing"
        "syncthing-gui-bridge"
      ]
      ++ lib.optional isClio "syncthing-home-lan-bridge"
      ++ [ "syncthing-init" ]
      ++ lib.optional isClio "syncthing-wireguard-tunnel";
      validFolder =
        folder:
        {
          id,
          label,
          path,
          ignorePatterns,
        }:
        folder.enable
        && folder.id == id
        && folder.path == path
        && folder.label == label
        && folder.filesystemType == "basic"
        && folder.type == "sendreceive"
        && folder.devices == peerNames
        && folder.rescanIntervalS == 3600
        && folder.fsWatcherEnabled
        && folder.fsWatcherDelayS == 1
        && folder.fsWatcherTimeoutS == 5
        && folder.scanProgressIntervalS == -1
        && folder.maxConcurrentWrites == 4
        && !folder.sendXattrs
        && !folder.syncXattrs
        && folder.ignorePatterns == ignorePatterns
        && folder.maxConflicts == 10
        && !folder.ignorePerms
        && folder.autoNormalize
        && !folder.syncOwnership
        && !folder.sendOwnership
        && !folder.copyOwnershipFromParent
        && !folder.disableFsync
        && folder.versioning.type == "staggered"
        && folder.versioning.cleanupIntervalS == 3600
        && folder.versioning.fsPath == ""
        && folder.versioning.fsType == "basic"
        && folder.versioning.params.maxAge == "31536000";
      validPeer =
        peerName:
        let
          peer = service.settings.devices.${peerName};
          peerPolicy = expectedNodes.${peerName};
        in
        validDeviceId peer.id
        && peer.addresses == peerPolicy.addresses
        && peer.allowedNetworks == peerPolicy.networks
        && !(builtins.elem "dynamic" peer.addresses)
        && peer.autoAcceptFolders == (isClio && peerName == "hera")
        && !peer.introducer
        && !peer.untrusted
        && !peer.paused
        && peer.compression == "metadata";
    in
    service.enable
    && !service.tray.enable
    && builtins.attrNames syncthingAgents == expectedAgentNames
    && service.package.version == "2.1.3"
    && service.cert == null
    && service.key == null
    && service.guiAddress == "${home.home.homeDirectory}/.local/state/syncthing/gui.sock"
    && service.guiCredentials == null
    && service.extraOptions == [ "--no-port-probing" ]
    && !service.overrideDevices
    && !service.overrideFolders
    && builtins.attrNames service.settings.devices == peerNames
    &&
      builtins.attrNames folders == [
        "desktop"
        "documents"
      ]
    && lib.all validPeer peerNames
    && validFolder documents {
      id = "documents";
      label = "Documents";
      path = "${home.home.homeDirectory}/Documents";
      ignorePatterns = defaultIgnorePatterns ++ [ "/.git" ];
    }
    && validFolder desktop {
      id = "desktop";
      label = "Desktop";
      path = "${home.home.homeDirectory}/Desktop";
      ignorePatterns = defaultIgnorePatterns;
    }
    && defaultFolder.path == "~/doc"
    && defaultFolder.fsWatcherEnabled
    && defaultFolder.fsWatcherDelayS == 1
    && defaultFolder.fsWatcherTimeoutS == 5
    && defaultFolder.rescanIntervalS == 3600
    && defaultFolder.scanProgressIntervalS == -1
    && defaultFolder.maxConcurrentWrites == 4
    && !defaultFolder.disableFsync
    && defaultIgnores.lines == defaultIgnorePatterns
    && builtins.length options.listenAddresses == 1
    && localAddress == localPolicy.listen
    && options.alwaysLocalNets == peerNetworks
    && !options.globalAnnounceEnabled
    && options.globalAnnounceServers == [ ]
    && !options.localAnnounceEnabled
    && !options.announceLANAddresses
    && !options.relaysEnabled
    && !options.natEnabled
    && options.stunServers == [ ]
    && options.reconnectionIntervalS == 5
    && options.maxFolderConcurrency == 1
    && !options.setLowPriority
    && options.urAccepted == -1
    && !options.crashReportingEnabled
    && options.autoUpgradeIntervalH == 0
    && !options.startBrowser
    && agent.enable
    && agent.domain == "gui"
    && agent.config.KeepAlive == true
    && agent.config.RunAtLoad
    && agent.config.ProcessType == "Interactive"
    && agent.config.LowPriorityIO
    && bridgeAgent.enable
    && bridgeAgent.domain == "gui"
    && builtins.length bridgeAgent.config.ProgramArguments == 3
    && lib.hasSuffix "/bin/socat" (builtins.elemAt bridgeAgent.config.ProgramArguments 0)
    &&
      builtins.elemAt bridgeAgent.config.ProgramArguments 1
      == "TCP4-LISTEN:8384,bind=127.0.0.1,reuseaddr,fork"
    &&
      builtins.elemAt bridgeAgent.config.ProgramArguments 2
      == "UNIX-CONNECT:${home.home.homeDirectory}/.local/state/syncthing/gui.sock"
    && bridgeAgent.config.RunAtLoad
    && bridgeAgent.config.KeepAlive == true
    && initAgent.enable
    && initAgent.domain == "gui"
    && initAgent.config.RunAtLoad
    && initAgent.config.KeepAlive.SuccessfulExit == false
    && initAgent.config.ThrottleInterval == 5
    && (
      if isClio then
        homeLanBridgeAgent.enable
        && homeLanBridgeAgent.domain == "gui"
        && builtins.length homeLanBridgeAgent.config.ProgramArguments == 1
        && lib.hasInfix "syncthing-home-lan-bridge" (
          builtins.head homeLanBridgeAgent.config.ProgramArguments
        )
        && homeLanBridgeAgent.config.RunAtLoad
        && homeLanBridgeAgent.config.StartInterval == 30
        && homeLanBridgeAgent.config.KeepAlive == null
        && wireGuardTunnelAgent.enable
        && wireGuardTunnelAgent.domain == "gui"
        && builtins.length wireGuardTunnelAgent.config.ProgramArguments == 1
        && lib.hasInfix "syncthing-wireguard-tunnel" (
          builtins.head wireGuardTunnelAgent.config.ProgramArguments
        )
        && wireGuardTunnelAgent.config.RunAtLoad
        && wireGuardTunnelAgent.config.StartInterval == 30
        && wireGuardTunnelAgent.config.KeepAlive == null
      else
        homeLanBridgeAgent == null && wireGuardTunnelAgent == null
    )
    && preflight.before == [ "setupLaunchAgents" ]
    && preflight.after == [ "linkGeneration" ]
    && lib.hasInfix "/bin/syncthing-bootstrap" preflight.data
    && lib.hasInfix "required private directory is missing or unsafe: $path" preflight.data
    && lib.hasInfix "${home.home.homeDirectory}/Documents" preflight.data
    && !lib.hasInfix "${home.home.homeDirectory}/doc/obsidian" preflight.data
    && lib.hasInfix "SessionLoginItems" preflight.data
    && lib.hasInfix "managed monitor child" preflight.data
    && lib.hasInfix "tmutil addexclusion" preflight.data
    && !ownsMutableState home;
in
assert hasSyncthingApp heraSystem;
assert hasSyncthingApp clioSystem;
assert managedSyncthing.version == clio.services.syncthing.package.version;
assert hasDormantSyncthingApp heraSystem;
assert hasDormantSyncthingApp clioSystem;
assert validDarwinHome hera "hera";
assert validDarwinHome clio "clio";
assert
  builtins.length (
    lib.unique [
      hera.services.syncthing.settings.devices.clio.id
      clio.services.syncthing.settings.devices.hera.id
      hera.services.syncthing.settings.devices.vulcan.id
    ]
  ) == 3;
assert builtins.all (home: !home.services.syncthing.enable && !ownsMutableState home) linuxHomes;
pkgs.runCommand "syncthing-home-contract"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.gnugrep
      pkgs.python3
      managedSyncthing
    ];
  }
  ''
    set -eu
    default_policy='${
      builtins.toJSON {
        folder = clio.services.syncthing.settings."defaults/folder";
        ignores = clio.services.syncthing.settings."defaults/ignores".lines;
      }
    }'
    primary_policy='${
      builtins.toJSON {
        deviceID = hera.services.syncthing.settings.devices.clio.id;
        addresses = [
          "tcp://10.7.0.2:22000"
          "tcp://192.168.7.2:22000"
        ];
        networks = [
          "10.7.0.2/32"
          "192.168.7.0/24"
        ];
        autoAcceptFolders = true;
      }
    }'
    secondary_policy='${
      builtins.toJSON {
        deviceID = hera.services.syncthing.settings.devices.vulcan.id;
        addresses = [ "tcp://192.168.7.3:22000" ];
        networks = [ "192.168.7.3/32" ];
        autoAcceptFolders = false;
      }
    }'
    roundtrip_primary_policy='${
      builtins.toJSON {
        deviceID = hera.services.syncthing.settings.devices.clio.id;
        addresses = [
          "tcp://10.7.0.2:22000"
          "tcp://192.168.7.2:22000"
        ];
        networks = [
          "10.7.0.2/32"
          "192.168.7.0/24"
        ];
        autoAcceptFolders = false;
      }
    }'
    bash -n ${heraPreflight}
    bash -n ${clioPreflight}
    bash -n ${clioHomeLanBridge}
    bash -n ${clioWireGuardTunnel}
    grep -F -- '-B "$route_interface"' ${clioWireGuardTunnel} >/dev/null
    grep -F -- '-b 10.6.0.2' ${clioWireGuardTunnel} >/dev/null
    grep -F -- '/bin/sleep 30' ${clioWireGuardTunnel} >/dev/null
    grep -F -- '/bin/sleep 30' ${clioHomeLanBridge} >/dev/null
    grep -F -- 'range=192.168.1.4/32,reuseaddr,fork' ${clioHomeLanBridge} >/dev/null
    cp ${../../config/syncthing-bootstrap.py} bootstrap.py
    cat > config.xml <<'XML'
    <configuration version="52">
      <device id="${clio.services.syncthing.settings.devices.hera.id}" name="local-test" />
      <device id="${hera.services.syncthing.settings.devices.clio.id}" name="peer-test" introducer="true">
        <address>dynamic</address>
        <allowedNetwork>0.0.0.0/0</allowedNetwork>
        <paused>true</paused>
        <autoAcceptFolders>true</autoAcceptFolders>
        <untrusted>true</untrusted>
      </device>
      <device id="${hera.services.syncthing.settings.devices.vulcan.id}" name="second-peer-test">
        <address>dynamic</address>
        <allowedNetwork>0.0.0.0/0</allowedNetwork>
        <paused>true</paused>
        <autoAcceptFolders>true</autoAcceptFolders>
        <untrusted>true</untrusted>
      </device>
      <device id="STALE-UNMANAGED-DEVICE" name="stale-test">
        <address>dynamic</address>
      </device>
      <folder id="future-folder" path="/Users/test/doc/Future">
        <device id="${clio.services.syncthing.settings.devices.hera.id}" />
        <device id="${hera.services.syncthing.settings.devices.clio.id}" />
      </folder>
      <folder id="obsidian" label="Obsidian" path="/Users/test/doc/obsidian">
        <device id="${clio.services.syncthing.settings.devices.hera.id}" />
        <device id="${hera.services.syncthing.settings.devices.clio.id}" />
        <device id="${hera.services.syncthing.settings.devices.vulcan.id}" />
      </folder>
      <folder id="desktop" path="/tmp/wrong-desktop">
        <device id="${clio.services.syncthing.settings.devices.hera.id}" />
        <device id="${hera.services.syncthing.settings.devices.clio.id}" />
      </folder>
      <gui enabled="true" tls="false" sendBasicAuthPrompt="false">
        <address>127.0.0.1:8384</address>
        <metricsWithoutAuth>false</metricsWithoutAuth>
        <apikey>synthetic-test-value</apikey>
      </gui>
      <options>
        <listenAddress>default</listenAddress>
        <globalAnnounceServer>default</globalAnnounceServer>
        <globalAnnounceEnabled>true</globalAnnounceEnabled>
        <localAnnounceEnabled>true</localAnnounceEnabled>
        <announceLANAddresses>true</announceLANAddresses>
        <relaysEnabled>true</relaysEnabled>
        <natEnabled>true</natEnabled>
        <stunServer>default</stunServer>
        <reconnectionIntervalS>20</reconnectionIntervalS>
        <urAccepted>0</urAccepted>
        <crashReportingEnabled>true</crashReportingEnabled>
        <autoUpgradeIntervalH>12</autoUpgradeIntervalH>
        <startBrowser>true</startBrowser>
      </options>
      <defaults>
        <folder path="~" />
      </defaults>
    </configuration>
    XML
    chmod 0600 config.xml

    common_args=(
      --config config.xml
      --local-device-id ${clio.services.syncthing.settings.devices.hera.id}
      --peer-policy "$primary_policy"
      --peer-policy "$secondary_policy"
      --listen-address tcp://10.7.0.1:22000
      --gui-socket /Users/test/.local/state/syncthing/gui.sock
      --default-policy "$default_policy"
      --documents /Users/test/Documents
      --desktop /Users/test/Desktop
    )

    if python3 bootstrap.py --check "''${common_args[@]}"; then
      echo "unhardened synthetic configuration passed validation" >&2
      exit 1
    else
      test "$?" -eq 3
    fi
    python3 bootstrap.py --apply "''${common_args[@]}"
    python3 bootstrap.py --check "''${common_args[@]}"

    policy_args=( "''${common_args[@]:2}" )
    BASE_CONFIG=config.xml \
      LOCAL_ID=${clio.services.syncthing.settings.devices.hera.id} \
      PEER_ID=${hera.services.syncthing.settings.devices.clio.id} \
      SECOND_PEER_ID=${hera.services.syncthing.settings.devices.vulcan.id} \
      python3 - <<'PY'
    import os
    import xml.etree.ElementTree as ET

    base = ET.parse(os.environ["BASE_CONFIG"])
    for path, device_ids in (
        (
            "/Users/test/not-the-managed-path",
            (os.environ["LOCAL_ID"], os.environ["PEER_ID"], os.environ["SECOND_PEER_ID"]),
        ),
        (
            "/Users/test/doc/obsidian",
            (os.environ["LOCAL_ID"], os.environ["PEER_ID"]),
        ),
    ):
        root = ET.fromstring(ET.tostring(base.getroot()))
        folder = ET.SubElement(root, "folder", {"id": "obsidian", "path": path})
        for device_id in device_ids:
            ET.SubElement(folder, "device", {"id": device_id})
        suffix = "path" if "not-the-managed" in path else "topology"
        ET.ElementTree(root).write(
            f"retained-obsidian-{suffix}.xml",
            encoding="utf-8",
            xml_declaration=True,
        )
    PY
    for retained_config in retained-obsidian-path.xml retained-obsidian-topology.xml; do
      python3 bootstrap.py --apply --config "$retained_config" "''${policy_args[@]}"
      python3 bootstrap.py --check --config "$retained_config" "''${policy_args[@]}"
      RETAINED_CONFIG="$retained_config" python3 - <<'PY'
    import os
    import xml.etree.ElementTree as ET

    root = ET.parse(os.environ["RETAINED_CONFIG"]).getroot()
    assert sum(folder.get("id") == "obsidian" for folder in root.findall("folder")) == 1
    PY
    done

    cp config.xml duplicate-sections.xml
    DUPLICATE_CONFIG=duplicate-sections.xml python3 - <<'PY'
    import os
    import xml.etree.ElementTree as ET

    path = os.environ["DUPLICATE_CONFIG"]
    tree = ET.parse(path)
    root = tree.getroot()
    duplicate_options = ET.SubElement(root, "options")
    ET.SubElement(duplicate_options, "listenAddress").text = "default"
    ET.SubElement(duplicate_options, "globalAnnounceEnabled").text = "true"
    duplicate_gui = ET.SubElement(root, "gui", {"enabled": "true"})
    ET.SubElement(duplicate_gui, "address").text = "0.0.0.0:8384"
    duplicate_defaults = ET.SubElement(root, "defaults")
    ET.SubElement(duplicate_defaults, "folder", {"path": "~"})
    tree.write(path, encoding="utf-8", xml_declaration=True)
    PY
    duplicate_before="$(python3 -c 'import hashlib; print(hashlib.sha256(open("duplicate-sections.xml", "rb").read()).hexdigest())')"
    if python3 bootstrap.py --check \
      --config duplicate-sections.xml \
      --local-device-id ${clio.services.syncthing.settings.devices.hera.id} \
      --peer-policy "$primary_policy" \
      --peer-policy "$secondary_policy" \
      --listen-address tcp://10.7.0.1:22000 \
      --gui-socket /Users/test/.local/state/syncthing/gui.sock \
      --default-policy "$default_policy" \
      --documents /Users/test/Documents \
      --desktop /Users/test/Desktop; then
      echo "duplicate policy sections passed validation" >&2
      exit 1
    else
      test "$?" -eq 2
    fi
    duplicate_after="$(python3 -c 'import hashlib; print(hashlib.sha256(open("duplicate-sections.xml", "rb").read()).hexdigest())')"
    test "$duplicate_before" = "$duplicate_after"

    if python3 bootstrap.py --check \
      --config config.xml \
      --local-device-id ABSENT-LOCAL-DEVICE \
      --peer-policy "$primary_policy" \
      --peer-policy "$secondary_policy" \
      --listen-address tcp://10.7.0.1:22000 \
      --gui-socket /Users/test/.local/state/syncthing/gui.sock \
      --default-policy "$default_policy" \
      --documents /Users/test/Documents \
      --desktop /Users/test/Desktop; then
      echo "mismatched synthetic identity passed validation" >&2
      exit 1
    else
      test "$?" -eq 2
    fi

    mkdir roundtrip
    syncthing generate --home roundtrip --no-port-probing >/dev/null 2>&1
    roundtrip_id="$(syncthing device-id --home roundtrip 2>/dev/null)"
    ROUNDTRIP=roundtrip/config.xml \
      PEER_ID=${hera.services.syncthing.settings.devices.clio.id} \
      SECOND_PEER_ID=${hera.services.syncthing.settings.devices.vulcan.id} \
      LOCAL_ID="$roundtrip_id" \
      python3 - <<'PY'
    import os
    import xml.etree.ElementTree as ET

    path = os.environ["ROUNDTRIP"]
    tree = ET.parse(path)
    root = tree.getroot()
    for peer_id in (os.environ["PEER_ID"], os.environ["SECOND_PEER_ID"]):
        peer = ET.SubElement(
            root,
            "device",
            {
                "id": peer_id,
                "name": "peer-test",
                "compression": "metadata",
                "introducer": "false",
                "skipIntroductionRemovals": "false",
                "introducedBy": "",
            },
        )
        ET.SubElement(peer, "address").text = "dynamic"
        ET.SubElement(peer, "allowedNetwork").text = "0.0.0.0/0"
        ET.SubElement(peer, "paused").text = "false"
        ET.SubElement(peer, "autoAcceptFolders").text = "false"
        ET.SubElement(peer, "untrusted").text = "false"
    for folder_id, label, folder_path in (
        ("obsidian", "Obsidian", "/Users/test/doc/obsidian"),
        ("desktop", "Desktop", "/Users/test/Desktop"),
        ("future-folder", "Future", "/Users/test/doc/Future"),
    ):
        folder = ET.SubElement(
            root,
            "folder",
            {
                "id": folder_id,
                "label": label,
                "path": folder_path,
                "type": "sendreceive",
            },
        )
        ET.SubElement(folder, "device", {"id": os.environ["LOCAL_ID"]})
        ET.SubElement(folder, "device", {"id": os.environ["PEER_ID"]})
        ET.SubElement(folder, "device", {"id": os.environ["SECOND_PEER_ID"]})
    tree.write(path, encoding="utf-8", xml_declaration=True)
    PY
    python3 bootstrap.py --apply \
      --config roundtrip/config.xml \
      --local-device-id "$roundtrip_id" \
      --peer-policy "$roundtrip_primary_policy" \
      --peer-policy "$secondary_policy" \
      --listen-address tcp://10.7.0.1:22000 \
      --gui-socket /Users/test/.local/state/syncthing/gui.sock \
      --default-policy "$default_policy" \
      --documents /Users/test/Documents \
      --desktop /Users/test/Desktop
    syncthing generate --home roundtrip --no-port-probing >/dev/null 2>&1
    python3 bootstrap.py --check \
      --config roundtrip/config.xml \
      --local-device-id "$roundtrip_id" \
      --peer-policy "$roundtrip_primary_policy" \
      --peer-policy "$secondary_policy" \
      --listen-address tcp://10.7.0.1:22000 \
      --gui-socket /Users/test/.local/state/syncthing/gui.sock \
      --default-policy "$default_policy" \
      --documents /Users/test/Documents \
      --desktop /Users/test/Desktop

    ROUNDTRIP=roundtrip/config.xml ROUNDTRIP_LOCAL="$roundtrip_id" \
      DEFAULT_POLICY="$default_policy" TOPOLOGY=${topologyFile} python3 - <<'PY'
    import base64
    import ipaddress
    import json
    import os
    import xml.etree.ElementTree as ET

    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    def check_digit(payload):
        factor = 1
        total = 0
        for character in payload:
            codepoint = alphabet.index(character)
            addend = factor * codepoint
            factor = 1 if factor == 2 else 2
            total += addend // 32 + addend % 32
        return alphabet[(32 - total % 32) % 32]

    def validate_device_id(value):
        compact = value.replace("-", "")
        assert len(compact) == 56
        payload = ""
        for offset in range(0, 56, 14):
            group = compact[offset : offset + 14]
            assert check_digit(group[:13]) == group[13]
            payload += group[:13]
        assert len(base64.b32decode(payload + "====")) == 32

    def xml_scalar(value):
        if isinstance(value, bool):
            return str(value).lower()
        if isinstance(value, float) and value.is_integer():
            return str(int(value))
        return str(value)

    def assert_default_policy(root, policy):
        folder = root.find("defaults/folder")
        expected_folder = policy["folder"]
        assert folder.get("path") == expected_folder["path"]
        assert_folder_policy(folder, expected_folder)
        ignores = root.find("defaults/ignores")
        assert [line.text for line in ignores.findall("line")] == policy["ignores"]

    def assert_folder_policy(folder, expected_folder):
        for attribute in (
            "rescanIntervalS",
            "fsWatcherEnabled",
            "fsWatcherDelayS",
            "fsWatcherTimeoutS",
        ):
            assert folder.get(attribute) == xml_scalar(expected_folder[attribute])
        for tag in ("scanProgressIntervalS", "maxConcurrentWrites", "disableFsync"):
            assert folder.findtext(tag) == xml_scalar(expected_folder[tag])

    with open(os.environ["TOPOLOGY"], encoding="utf-8") as source:
        topology = json.load(source)
    default_policy = json.loads(os.environ["DEFAULT_POLICY"])
    expected = {
        "hera": {
            "addresses": ["tcp://127.0.0.1:22001"],
            "listen": "tcp://192.168.1.4:22000",
            "networks": ["192.168.1.4/32", "127.0.0.1/32"],
        },
        "clio": {
            "addresses": ["tcp://clio.lan:22000"],
            "listen": "tcp://127.0.0.1:22000",
            "networks": ["192.168.1.5/32", "192.168.1.4/32"],
        },
        "vulcan": {
            "addresses": ["tcp://192.168.1.2:22000"],
            "listen": "tcp://192.168.1.2:22000",
            "networks": ["192.168.1.2/32"],
        },
    }
    tailscale_network = ipaddress.ip_network("100.64.0.0/10")
    assert set(topology) == {"hera", "clio", "vulcan"}
    assert len({node["id"] for node in topology.values()}) == 3
    for name, node in topology.items():
        validate_device_id(node["id"])
        assert {key: value for key, value in node.items() if key != "id"} == expected[name]
        for network in node["networks"]:
            assert not ipaddress.ip_network(network, strict=True).overlaps(tailscale_network)

    root = ET.parse("config.xml").getroot()
    options = root.find("options")
    gui = root.find("gui")
    devices = {device.get("id"): device for device in root.findall("device")}
    assert set(devices) == {
        topology["hera"]["id"],
        topology["clio"]["id"],
        topology["vulcan"]["id"],
    }
    peer = devices[topology["clio"]["id"]]
    assert [node.text for node in peer.findall("address")] == [
        "tcp://10.7.0.2:22000",
        "tcp://192.168.7.2:22000",
    ]
    assert [node.text for node in peer.findall("allowedNetwork")] == [
        "10.7.0.2/32",
        "192.168.7.0/24",
    ]
    assert peer.get("introducer") == "false"
    assert peer.findtext("paused") == "false"
    assert peer.findtext("autoAcceptFolders") == "true"
    assert peer.findtext("untrusted") == "false"
    second_peer = devices[topology["vulcan"]["id"]]
    assert [node.text for node in second_peer.findall("address")] == [
        "tcp://192.168.7.3:22000"
    ]
    assert [node.text for node in second_peer.findall("allowedNetwork")] == [
        "192.168.7.3/32"
    ]
    assert second_peer.findtext("autoAcceptFolders") == "false"
    folders = {folder.get("id"): folder for folder in root.findall("folder")}
    assert set(folders) == {"documents", "desktop", "future-folder"}
    assert folders["documents"].get("path") == "/Users/test/Documents"
    assert folders["desktop"].get("path") == "/Users/test/Desktop"
    assert folders["future-folder"].get("path") == "/Users/test/doc/Future"
    for folder_id in ("documents", "desktop"):
        folder = folders[folder_id]
        assert folder.get("type") == "sendreceive"
        assert {device.get("id") for device in folder.findall("device")} == {
            topology["hera"]["id"],
            topology["clio"]["id"],
            topology["vulcan"]["id"],
        }
        assert folder.findtext("paused") == "false"
    for folder in folders.values():
        assert_folder_policy(folder, default_policy["folder"])
    assert [node.text for node in options.findall("listenAddress")] == ["tcp://10.7.0.1:22000"]
    assert [node.text for node in options.findall("alwaysLocalNet")] == [
        "10.7.0.2/32",
        "192.168.7.0/24",
        "192.168.7.3/32",
    ]
    assert [node.text for node in options.findall("globalAnnounceServer")] == ["default"]
    assert [node.text for node in options.findall("stunServer")] == ["default"]
    for tag in (
        "globalAnnounceEnabled",
        "localAnnounceEnabled",
        "announceLANAddresses",
        "relaysEnabled",
        "natEnabled",
        "crashReportingEnabled",
        "startBrowser",
    ):
        assert options.findtext(tag) == "false"
    assert options.findtext("reconnectionIntervalS") == "5"
    assert options.findtext("urAccepted") == "-1"
    assert options.findtext("autoUpgradeIntervalH") == "0"
    assert gui.findtext("address") == "/Users/test/.local/state/syncthing/gui.sock"
    assert gui.findtext("unixSocketPermissions") == "0600"
    assert gui.findtext("apikey") == "synthetic-test-value"
    assert_default_policy(root, default_policy)

    # Syncthing 2.1.3 reloads absent default-tagged server slices as "default".
    # The disabling booleans, not empty XML slices, are the fail-closed authority.
    roundtrip_root = ET.parse(os.environ["ROUNDTRIP"]).getroot()
    roundtrip_options = roundtrip_root.find("options")
    roundtrip_devices = {device.get("id"): device for device in roundtrip_root.findall("device")}
    assert set(roundtrip_devices) == {
        os.environ["ROUNDTRIP_LOCAL"],
        topology["clio"]["id"],
        topology["vulcan"]["id"],
    }
    roundtrip_peer = roundtrip_devices[topology["clio"]["id"]]
    assert [node.text for node in roundtrip_peer.findall("address")] == [
        "tcp://10.7.0.2:22000",
        "tcp://192.168.7.2:22000",
    ]
    assert [node.text for node in roundtrip_peer.findall("allowedNetwork")] == [
        "10.7.0.2/32",
        "192.168.7.0/24",
    ]
    roundtrip_second_peer = roundtrip_devices[topology["vulcan"]["id"]]
    assert [node.text for node in roundtrip_second_peer.findall("address")] == [
        "tcp://192.168.7.3:22000"
    ]
    assert [node.text for node in roundtrip_second_peer.findall("allowedNetwork")] == [
        "192.168.7.3/32"
    ]
    assert [node.text for node in roundtrip_options.findall("alwaysLocalNet")] == [
        "10.7.0.2/32",
        "192.168.7.0/24",
        "192.168.7.3/32",
    ]
    roundtrip_folders = {
        folder.get("id"): folder for folder in roundtrip_root.findall("folder")
    }
    assert set(roundtrip_folders) == {"documents", "desktop", "future-folder"}
    assert roundtrip_folders["documents"].get("path") == "/Users/test/Documents"
    assert roundtrip_folders["desktop"].get("path") == "/Users/test/Desktop"
    assert roundtrip_folders["future-folder"].get("path") == "/Users/test/doc/Future"
    for folder in roundtrip_folders.values():
        assert {device.get("id") for device in folder.findall("device")} == {
            os.environ["ROUNDTRIP_LOCAL"],
            topology["clio"]["id"],
            topology["vulcan"]["id"],
        }
        assert_folder_policy(folder, default_policy["folder"])
    assert_default_policy(roundtrip_root, default_policy)
    assert [node.text for node in roundtrip_options.findall("globalAnnounceServer")] == ["default"]
    assert [node.text for node in roundtrip_options.findall("stunServer")] == ["default"]
    assert roundtrip_options.findtext("globalAnnounceEnabled") == "false"
    assert roundtrip_options.findtext("natEnabled") == "false"
    assert roundtrip_options.findtext("relaysEnabled") == "false"
    assert roundtrip_options.findtext("localAnnounceEnabled") == "false"
    PY

    ROUNDTRIP=roundtrip/config.xml python3 - <<'PY'
    import os
    import xml.etree.ElementTree as ET

    path = os.environ["ROUNDTRIP"]
    tree = ET.parse(path)
    options = tree.getroot().find("options")
    for tag in ("globalAnnounceServer", "stunServer"):
        for node in list(options.findall(tag)):
            options.remove(node)
    tree.write(path, encoding="utf-8", xml_declaration=True)
    PY
    python3 bootstrap.py --check \
      --config roundtrip/config.xml \
      --local-device-id "$roundtrip_id" \
      --peer-policy "$roundtrip_primary_policy" \
      --peer-policy "$secondary_policy" \
      --listen-address tcp://10.7.0.1:22000 \
      --gui-socket /Users/test/.local/state/syncthing/gui.sock \
      --default-policy "$default_policy" \
      --documents /Users/test/Documents \
      --desktop /Users/test/Desktop

    touch "$out"
  ''
