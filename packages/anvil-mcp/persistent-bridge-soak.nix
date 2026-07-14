{
  anvilMcp,
  bash,
  coreutils,
  python3,
  runCommand,
  unixtools,
}:

runCommand "anvil-mcp-persistent-soak"
  {
    nativeBuildInputs = [
      anvilMcp
      anvilMcp.dedicatedEmacs
      coreutils
      python3
    ];
  }
  ''
    ${coreutils}/bin/timeout --signal=TERM --kill-after=60 420 \
      ${python3}/bin/python3 -I -B -u \
      ${./persistent-bridge-soak-test.py} \
      ${./persistent-bridge-soak.py} \
      ${./agent-supervisor-smoke.py} \
      ${./agent-supervisor.py} \
      ${toString anvilMcp.timeoutPolicy.watchdogHeartbeatSeconds} \
      ${toString anvilMcp.timeoutPolicy.watchdogDispatchSeconds}

    soak_home=$(mktemp -d /tmp/ah.XXXXXX)
    soak_runtime_root=$(mktemp -d /tmp/ar.XXXXXX)
    soak_state_root=$(mktemp -d /tmp/as.XXXXXX)
    cleanup() {
      status=$?
      rm -rf "$soak_home" "$soak_runtime_root" "$soak_state_root"
      return "$status"
    }
    trap cleanup EXIT

    ${coreutils}/bin/env -u XDG_CONFIG_HOME \
      HOME="$soak_home" \
      SHELL="${bash}/bin/bash" \
      ANVIL_EMACS_RUNTIME_ROOT="$soak_runtime_root" \
      ANVIL_EMACS_STATE_ROOT="$soak_state_root" \
      ANVIL_EMACS_LOCK_REFRESH_SECONDS=0.2 \
      ANVIL_PER_AGENT_LAUNCHER="${anvilMcp}/bin/anvil-mcp" \
      ANVIL_PERSISTENT_SOAK_CYCLES=25 \
      ANVIL_PERSISTENT_SOAK_HEALTHY_SECONDS=${toString anvilMcp.timeoutPolicy.clientToolSeconds} \
      ANVIL_SMOKE_WATCHDOG_NORMAL_SECONDS=${toString anvilMcp.timeoutPolicy.watchdogHeartbeatSeconds} \
      ANVIL_SMOKE_WATCHDOG_DISPATCH_SECONDS=${toString anvilMcp.timeoutPolicy.watchdogDispatchSeconds} \
      ${coreutils}/bin/timeout --signal=TERM --kill-after=60 1800 \
      ${python3}/bin/python3 -I -B -u \
      ${anvilMcp.dedicatedPersistentBridgeSoak} \
      ${anvilMcp}/bin/anvil-mcp \
      ${anvilMcp.dedicatedAgentSupervisor} \
      ${anvilMcp.dedicatedAgentSupervisorSmoke} \
      ${anvilMcp.git}/bin/git \
      ${anvilMcp.direnv}/bin/direnv \
      ${unixtools.ps}/bin/ps

    touch "$out"
  ''
