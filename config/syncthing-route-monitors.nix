{
  monitorLibrary,
  tools,
}:

{
  wireGuardTunnel = ''
    set -euo pipefail

    wireguard_route_active() {
      local route_interface
      route_interface="$(
        ${tools.route} -n get 192.168.1.3 2>/dev/null \
          | ${tools.awk} '/^[[:space:]]*interface: / { print $2; exit }'
      )" || return 1
      [ -n "$route_interface" ] \
        && ${tools.ifconfig} "$route_interface" 2>/dev/null \
          | ${tools.awk} '$1 == "inet" && $2 == "10.6.0.2" { found = 1 } END { exit !found }' \
        || return 1
      ${tools.printf} '%s\n' "$route_interface"
    }

    start_tunnel() {
      exec ${tools.ssh} \
        -N -T \
        -B "$1" \
        -b 10.6.0.2 \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 \
        -o ControlMaster=no \
        -o ControlPath=none \
        -o ExitOnForwardFailure=yes \
        -o ForwardAgent=no \
        -o HostName=192.168.1.3 \
        -o PermitLocalCommand=no \
        -o ProxyCommand=none \
        -o ProxyJump=none \
        -o ServerAliveCountMax=3 \
        -o ServerAliveInterval=15 \
        -o StrictHostKeyChecking=yes \
        -L 127.0.0.1:22001:192.168.1.3:22000 \
        hera
    }

    source ${monitorLibrary}
    syncthing_monitor wireguard_route_active start_tunnel ${tools.sleep} 30
  '';

  homeLanBridge = ''
    set -euo pipefail

    home_route_active() {
      local route_interface
      route_interface="$(
        ${tools.route} -n get 192.168.1.3 2>/dev/null \
          | ${tools.awk} '/^[[:space:]]*interface: / { print $2; exit }'
      )" || return 1
      case "$route_interface" in
        "" | utun*) return 1 ;;
      esac
      ${tools.ifconfig} "$route_interface" 2>/dev/null \
        | ${tools.awk} '$1 == "inet" && $2 == "192.168.1.5" { found = 1 } END { exit !found }' \
        || return 1
      ${tools.printf} '%s\n' "$route_interface"
    }

    start_bridge() {
      exec ${tools.socat} \
        "TCP4-LISTEN:22000,bind=192.168.1.5,range=192.168.1.3/32,reuseaddr,fork" \
        "TCP4:127.0.0.1:22000"
    }

    home_route_active >/dev/null || exit 0
    ${tools.ssh} \
      -T \
      -b 192.168.1.5 \
      -o BatchMode=yes \
      -o ClearAllForwardings=yes \
      -o ConnectTimeout=3 \
      -o ConnectionAttempts=1 \
      -o ControlMaster=no \
      -o ControlPath=none \
      -o ForwardAgent=no \
      -o HostName=192.168.1.3 \
      -o PermitLocalCommand=no \
      -o ProxyCommand=none \
      -o ProxyJump=none \
      -o StrictHostKeyChecking=yes \
      hera ${tools.remoteTrue} </dev/null

    source ${monitorLibrary}
    syncthing_monitor home_route_active start_bridge ${tools.sleep} 30
  '';
}
