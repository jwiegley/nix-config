{
  darwinConfigurations,
  homeConfigurations,
  nixosHomeEvaluationFixtures,
  pkgs,
}:

let
  inherit (pkgs) lib;
  heraSystem = darwinConfigurations.hera.config;
  clioSystem = darwinConfigurations.clio.config;
  hera = heraSystem.home-manager.users.johnw;
  clio = clioSystem.home-manager.users.johnw;
  topologyFile = pkgs.writeText "syncthing-topology.json" (
    builtins.toJSON {
      hera = {
        id = clio.services.syncthing.settings.devices.hera.id;
        listen = builtins.head hera.services.syncthing.settings.options.listenAddresses;
        peer = builtins.head hera.services.syncthing.settings.devices.clio.addresses;
        network = builtins.head hera.services.syncthing.settings.devices.clio.allowedNetworks;
      };
      clio = {
        id = hera.services.syncthing.settings.devices.clio.id;
        listen = builtins.head clio.services.syncthing.settings.options.listenAddresses;
        peer = builtins.head clio.services.syncthing.settings.devices.hera.addresses;
        network = builtins.head clio.services.syncthing.settings.devices.hera.allowedNetworks;
      };
    }
  );
  heraPreflight = pkgs.writeText "syncthing-hera-preflight" hera.home.activation.prepareSyncthing.data;
  clioPreflight = pkgs.writeText "syncthing-clio-preflight" clio.home.activation.prepareSyncthing.data;
  linuxHomes =
    map (fixture: fixture.config) (builtins.attrValues nixosHomeEvaluationFixtures)
    ++ map (configuration: configuration.config) (builtins.attrValues homeConfigurations);
  validDeviceId = id: builtins.match "[A-Z2-7]{7}(-[A-Z2-7]{7}){7}" id != null;
  endpointIP = endpoint: lib.removeSuffix ":22000" (lib.removePrefix "tcp://" endpoint);
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
      path == ".obsidian"
      || lib.hasPrefix ".obsidian/" path
      || lib.hasPrefix "Library/Application Support/Syncthing/" path
    ) (builtins.attrNames home.home.file);
  validDarwinHome =
    home: peerName:
    let
      service = home.services.syncthing;
      peer = service.settings.devices.${peerName};
      folder = service.settings.folders.obsidian;
      options = service.settings.options;
      localAddress = builtins.head options.listenAddresses;
      peerAddress = builtins.head peer.addresses;
      agent = home.launchd.agents.syncthing;
      initAgent = home.launchd.agents.syncthing-init;
      preflight = home.home.activation.prepareSyncthing;
      syncthingAgents = lib.filterAttrs (name: _: lib.hasInfix "syncthing" name) home.launchd.agents;
    in
    service.enable
    && !service.tray.enable
    &&
      builtins.attrNames syncthingAgents == [
        "syncthing"
        "syncthing-init"
      ]
    && service.package.version == "2.1.2"
    && service.cert == null
    && service.key == null
    && service.guiAddress == "${home.home.homeDirectory}/.local/state/syncthing/gui.sock"
    && service.guiCredentials == null
    && service.extraOptions == [ "--no-port-probing" ]
    && service.overrideDevices
    && service.overrideFolders
    && builtins.attrNames service.settings.devices == [ peerName ]
    && builtins.attrNames service.settings.folders == [ "obsidian" ]
    && validDeviceId peer.id
    && builtins.length peer.addresses == 1
    && lib.hasPrefix "tcp://100." peerAddress
    && lib.hasSuffix ":22000" peerAddress
    && peer.allowedNetworks == [ "${endpointIP peerAddress}/32" ]
    && !(builtins.elem "dynamic" peer.addresses)
    && !peer.autoAcceptFolders
    && !peer.introducer
    && !peer.untrusted
    && !peer.paused
    && peer.compression == "metadata"
    && folder.enable
    && folder.id == "obsidian"
    && folder.path == "${home.home.homeDirectory}/.obsidian"
    && folder.label == "Obsidian"
    && folder.filesystemType == "basic"
    && folder.type == "sendreceive"
    && folder.devices == [ peerName ]
    && folder.rescanIntervalS == 300
    && folder.fsWatcherEnabled
    && folder.fsWatcherDelayS == 1
    && folder.fsWatcherTimeoutS == 0
    && folder.sendXattrs
    && folder.syncXattrs
    && folder.xattrFilter.entries == [ ]
    && folder.xattrFilter.maxSingleEntrySize == 16777216
    && folder.xattrFilter.maxTotalSize == 67108864
    && folder.ignorePatterns == [ "(?d).DS_Store" ]
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
    && folder.versioning.params.maxAge == "31536000"
    && builtins.length options.listenAddresses == 1
    && lib.hasPrefix "tcp://100." localAddress
    && lib.hasSuffix ":22000" localAddress
    && localAddress != peerAddress
    && options.alwaysLocalNets == peer.allowedNetworks
    && !options.globalAnnounceEnabled
    && options.globalAnnounceServers == [ ]
    && !options.localAnnounceEnabled
    && !options.announceLANAddresses
    && !options.relaysEnabled
    && !options.natEnabled
    && options.stunServers == [ ]
    && options.reconnectionIntervalS == 5
    && options.urAccepted == -1
    && !options.crashReportingEnabled
    && options.autoUpgradeIntervalH == 0
    && !options.startBrowser
    && agent.enable
    && agent.domain == "gui"
    && agent.config.KeepAlive == true
    && agent.config.RunAtLoad
    && initAgent.enable
    && initAgent.domain == "gui"
    && initAgent.config.RunAtLoad
    && initAgent.config.KeepAlive.SuccessfulExit == false
    && initAgent.config.ThrottleInterval == 5
    && preflight.before == [ "setupLaunchAgents" ]
    && preflight.after == [ "linkGeneration" ]
    && lib.hasInfix "syncthing-bootstrap" preflight.data
    && lib.hasInfix "SessionLoginItems" preflight.data
    && lib.hasInfix "unmanaged or duplicate Syncthing daemon" preflight.data
    && !ownsMutableState home;
in
assert hasSyncthingApp heraSystem;
assert hasSyncthingApp clioSystem;
assert hasDormantSyncthingApp heraSystem;
assert hasDormantSyncthingApp clioSystem;
assert validDarwinHome hera "clio";
assert validDarwinHome clio "hera";
assert
  hera.services.syncthing.settings.devices.clio.id
  != clio.services.syncthing.settings.devices.hera.id;
assert builtins.all (home: !home.services.syncthing.enable && !ownsMutableState home) linuxHomes;
pkgs.runCommand "syncthing-home-contract"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.python3
      pkgs.syncthing
    ];
  }
  ''
    set -eu
    bash -n ${heraPreflight}
    bash -n ${clioPreflight}
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
      <device id="STALE-UNMANAGED-DEVICE" name="stale-test">
        <address>dynamic</address>
      </device>
      <folder id="stale-folder" path="/tmp/stale">
        <device id="STALE-UNMANAGED-DEVICE" />
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
    </configuration>
    XML
    chmod 0600 config.xml

    common_args="--config config.xml \
      --local-device-id ${clio.services.syncthing.settings.devices.hera.id} \
      --peer-device-id ${hera.services.syncthing.settings.devices.clio.id} \
      --peer-address tcp://100.64.0.2:22000 \
      --listen-address tcp://100.64.0.1:22000 \
      --peer-network 100.64.0.2/32 \
      --gui-socket /Users/test/.local/state/syncthing/gui.sock \
      --vault /Users/test/.obsidian"

    if python3 bootstrap.py --check $common_args; then
      echo "unhardened synthetic configuration passed validation" >&2
      exit 1
    else
      test "$?" -eq 3
    fi
    python3 bootstrap.py --apply $common_args
    python3 bootstrap.py --check $common_args

    if python3 bootstrap.py --check \
      --config config.xml \
      --local-device-id ABSENT-LOCAL-DEVICE \
      --peer-device-id ${hera.services.syncthing.settings.devices.clio.id} \
      --peer-address tcp://100.64.0.2:22000 \
      --listen-address tcp://100.64.0.1:22000 \
      --peer-network 100.64.0.2/32 \
      --gui-socket /Users/test/.local/state/syncthing/gui.sock \
      --vault /Users/test/.obsidian; then
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
      LOCAL_ID="$roundtrip_id" \
      python3 - <<'PY'
    import os
    import xml.etree.ElementTree as ET

    path = os.environ["ROUNDTRIP"]
    tree = ET.parse(path)
    root = tree.getroot()
    peer = ET.SubElement(
        root,
        "device",
        {
            "id": os.environ["PEER_ID"],
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
    folder = ET.SubElement(
        root,
        "folder",
        {
            "id": "obsidian",
            "label": "Obsidian",
            "path": "/Users/test/.obsidian",
            "type": "sendreceive",
        },
    )
    ET.SubElement(folder, "device", {"id": os.environ["LOCAL_ID"]})
    ET.SubElement(folder, "device", {"id": os.environ["PEER_ID"]})
    tree.write(path, encoding="utf-8", xml_declaration=True)
    PY
    python3 bootstrap.py --apply \
      --config roundtrip/config.xml \
      --local-device-id "$roundtrip_id" \
      --peer-device-id ${hera.services.syncthing.settings.devices.clio.id} \
      --peer-address tcp://100.64.0.2:22000 \
      --listen-address tcp://100.64.0.1:22000 \
      --peer-network 100.64.0.2/32 \
      --gui-socket /Users/test/.local/state/syncthing/gui.sock \
      --vault /Users/test/.obsidian
    syncthing generate --home roundtrip --no-port-probing >/dev/null 2>&1
    python3 bootstrap.py --check \
      --config roundtrip/config.xml \
      --local-device-id "$roundtrip_id" \
      --peer-device-id ${hera.services.syncthing.settings.devices.clio.id} \
      --peer-address tcp://100.64.0.2:22000 \
      --listen-address tcp://100.64.0.1:22000 \
      --peer-network 100.64.0.2/32 \
      --gui-socket /Users/test/.local/state/syncthing/gui.sock \
      --vault /Users/test/.obsidian

    ROUNDTRIP=roundtrip/config.xml ROUNDTRIP_LOCAL="$roundtrip_id" \
      TOPOLOGY=${topologyFile} python3 - <<'PY'
    import base64
    import ipaddress
    import json
    import os
    import urllib.parse
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

    def endpoint_ip(endpoint):
        parsed = urllib.parse.urlparse(endpoint)
        assert parsed.scheme == "tcp" and parsed.port == 22000
        return ipaddress.ip_address(parsed.hostname)

    with open(os.environ["TOPOLOGY"], encoding="utf-8") as source:
        topology = json.load(source)
    shared = ipaddress.ip_network("100.64.0.0/10")
    assert set(topology) == {"hera", "clio"}
    assert topology["hera"]["id"] != topology["clio"]["id"]
    for local_name, peer_name in (("hera", "clio"), ("clio", "hera")):
        local = topology[local_name]
        peer = topology[peer_name]
        validate_device_id(local["id"])
        local_ip = endpoint_ip(local["listen"])
        peer_ip = endpoint_ip(local["peer"])
        network = ipaddress.ip_network(local["network"], strict=True)
        assert local_ip in shared and peer_ip in shared
        assert local["peer"] == peer["listen"]
        assert network.prefixlen == 32 and network.network_address == peer_ip

    root = ET.parse("config.xml").getroot()
    options = root.find("options")
    gui = root.find("gui")
    devices = {device.get("id"): device for device in root.findall("device")}
    assert set(devices) == {
        topology["hera"]["id"],
        topology["clio"]["id"],
    }
    peer = devices[topology["clio"]["id"]]
    assert [node.text for node in peer.findall("address")] == ["tcp://100.64.0.2:22000"]
    assert [node.text for node in peer.findall("allowedNetwork")] == ["100.64.0.2/32"]
    assert peer.get("introducer") == "false"
    assert peer.findtext("paused") == "false"
    assert peer.findtext("autoAcceptFolders") == "false"
    assert peer.findtext("untrusted") == "false"
    assert root.findall("folder") == []
    assert [node.text for node in options.findall("listenAddress")] == ["tcp://100.64.0.1:22000"]
    assert [node.text for node in options.findall("alwaysLocalNet")] == ["100.64.0.2/32"]
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

    # Syncthing 2.1.2 reloads absent default-tagged server slices as "default".
    # The disabling booleans, not empty XML slices, are the fail-closed authority.
    roundtrip_root = ET.parse(os.environ["ROUNDTRIP"]).getroot()
    roundtrip_options = roundtrip_root.find("options")
    roundtrip_devices = {device.get("id"): device for device in roundtrip_root.findall("device")}
    assert set(roundtrip_devices) == {
        os.environ["ROUNDTRIP_LOCAL"],
        topology["clio"]["id"],
    }
    roundtrip_peer = roundtrip_devices[topology["clio"]["id"]]
    assert [node.text for node in roundtrip_peer.findall("address")] == ["tcp://100.64.0.2:22000"]
    assert [node.text for node in roundtrip_peer.findall("allowedNetwork")] == ["100.64.0.2/32"]
    roundtrip_folder = roundtrip_root.find("folder[@id='obsidian']")
    assert roundtrip_folder is not None
    assert {
        device.get("id") for device in roundtrip_folder.findall("device")
    } == {
        os.environ["ROUNDTRIP_LOCAL"],
        topology["clio"]["id"],
    }
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
      --peer-device-id ${hera.services.syncthing.settings.devices.clio.id} \
      --peer-address tcp://100.64.0.2:22000 \
      --listen-address tcp://100.64.0.1:22000 \
      --peer-network 100.64.0.2/32 \
      --gui-socket /Users/test/.local/state/syncthing/gui.sock \
      --vault /Users/test/.obsidian

    touch "$out"
  ''
