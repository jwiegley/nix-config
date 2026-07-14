{
  anvilMcp,
  bash,
  coreutils,
  python3,
  runCommand,
  unixtools,
}:

let
  policy = anvilMcp.timeoutPolicy;
  soakCycles = 25;
  watchdogResponseGraceSeconds = 30;
  watchdogWindowSeconds =
    if policy.watchdogHeartbeatSeconds < policy.watchdogDispatchSeconds then
      policy.watchdogHeartbeatSeconds
    else
      policy.watchdogDispatchSeconds;
  watchdogResponseBudgetSeconds = watchdogWindowSeconds + watchdogResponseGraceSeconds;

  # Nonce creation precedes healthy-sibling work, and both must finish before
  # the hung request's absolute watchdog deadline.  After that response, one
  # cycle has explicit restart, old-root exit, readiness, and scheduling
  # envelopes.
  soakNonceStartSeconds = 10;
  soakHealthySeconds = watchdogWindowSeconds - soakNonceStartSeconds;
  soakRestartSeconds = 2 * policy.bridgeReadinessSeconds;
  soakReadinessSeconds = watchdogWindowSeconds;
  soakCycleBudgetSeconds =
    watchdogResponseBudgetSeconds
    + soakRestartSeconds
    + policy.bridgeReadinessSeconds
    + soakReadinessSeconds
    + policy.frameReadSeconds;

  # Fixed work is split into enforced phases rather than an opaque allowance.
  # Setup covers two bridge boot/warmup envelopes, the yielding proof, and two
  # async-isolation checks.  Inventory, two bounded closes, and post-cleanup
  # verification each have their own process-local alarm in the driver.
  soakSetupSeconds =
    2 * (policy.bridgeDispatchSeconds + policy.clientToolSeconds)
    + watchdogResponseBudgetSeconds
    + 2 * watchdogWindowSeconds;
  soakInventorySeconds = 3 * policy.frameReadSeconds;
  soakCleanupSchedulingGraceSeconds = 2 * policy.frameReadSeconds;
  soakBridgeCleanupSeconds = 2 * policy.bridgeReadinessSeconds + soakCleanupSchedulingGraceSeconds;
  soakPostCleanupSeconds = policy.watchdogDispatchSeconds;
  soakInternalBudgetSeconds =
    soakSetupSeconds
    + soakCycles * soakCycleBudgetSeconds
    + soakInventorySeconds
    + soakBridgeCleanupSeconds
    + soakPostCleanupSeconds;
  soakMarginPercent = 20;
  soakMarginSeconds = builtins.div (soakInternalBudgetSeconds * soakMarginPercent + 99) 100;
  soakTimeoutSeconds = soakInternalBudgetSeconds + soakMarginSeconds;
in
assert soakHealthySeconds > 0;
assert soakNonceStartSeconds + soakHealthySeconds <= watchdogWindowSeconds;
assert soakMarginSeconds * 100 >= soakInternalBudgetSeconds * soakMarginPercent;
assert soakTimeoutSeconds > soakInternalBudgetSeconds;
assert soakTimeoutSeconds <= 2 * 60 * 60;
runCommand "anvil-mcp-persistent-soak"
  {
    nativeBuildInputs = [
      anvilMcp
      anvilMcp.dedicatedEmacs
      coreutils
      python3
    ];
    passthru.timeoutBudget = {
      cycles = soakCycles;
      cycleSeconds = soakCycleBudgetSeconds;
      setupSeconds = soakSetupSeconds;
      nonceStartSeconds = soakNonceStartSeconds;
      healthySeconds = soakHealthySeconds;
      restartSeconds = soakRestartSeconds;
      readinessSeconds = soakReadinessSeconds;
      inventorySeconds = soakInventorySeconds;
      bridgeCleanupSeconds = soakBridgeCleanupSeconds;
      cleanupSchedulingGraceSeconds = soakCleanupSchedulingGraceSeconds;
      postCleanupSeconds = soakPostCleanupSeconds;
      internalSeconds = soakInternalBudgetSeconds;
      marginPercent = soakMarginPercent;
      marginSeconds = soakMarginSeconds;
      timeoutSeconds = soakTimeoutSeconds;
    };
  }
  ''
    ${coreutils}/bin/timeout --signal=TERM --kill-after=60 420 \
      ${coreutils}/bin/env \
      ANVIL_PERSISTENT_SOAK_SETUP_SECONDS=${toString soakSetupSeconds} \
      ANVIL_PERSISTENT_SOAK_CYCLE_SECONDS=${toString soakCycleBudgetSeconds} \
      ANVIL_PERSISTENT_SOAK_INVENTORY_SECONDS=${toString soakInventorySeconds} \
      ANVIL_PERSISTENT_SOAK_BRIDGE_CLEANUP_SECONDS=${toString soakBridgeCleanupSeconds} \
      ANVIL_PERSISTENT_SOAK_POST_CLEANUP_SECONDS=${toString soakPostCleanupSeconds} \
      ANVIL_PERSISTENT_SOAK_HEALTHY_SECONDS=${toString soakHealthySeconds} \
      ANVIL_PERSISTENT_SOAK_RESTART_SECONDS=${toString soakRestartSeconds} \
      ANVIL_PERSISTENT_SOAK_READINESS_SECONDS=${toString soakReadinessSeconds} \
      ${python3}/bin/python3 -I -B -u \
      ${./persistent-bridge-soak-test.py} \
      ${./persistent-bridge-soak.py} \
      ${./agent-supervisor-smoke.py} \
      ${./agent-supervisor.py} \
      ${toString anvilMcp.timeoutPolicy.watchdogHeartbeatSeconds} \
      ${toString anvilMcp.timeoutPolicy.watchdogDispatchSeconds} \
      ${toString soakCycles} \
      ${toString soakMarginPercent} \
      ${toString soakTimeoutSeconds}

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
      ANVIL_PERSISTENT_SOAK_CYCLES=${toString soakCycles} \
      ANVIL_PERSISTENT_SOAK_SETUP_SECONDS=${toString soakSetupSeconds} \
      ANVIL_PERSISTENT_SOAK_CYCLE_SECONDS=${toString soakCycleBudgetSeconds} \
      ANVIL_PERSISTENT_SOAK_INVENTORY_SECONDS=${toString soakInventorySeconds} \
      ANVIL_PERSISTENT_SOAK_BRIDGE_CLEANUP_SECONDS=${toString soakBridgeCleanupSeconds} \
      ANVIL_PERSISTENT_SOAK_POST_CLEANUP_SECONDS=${toString soakPostCleanupSeconds} \
      ANVIL_PERSISTENT_SOAK_HEALTHY_SECONDS=${toString soakHealthySeconds} \
      ANVIL_PERSISTENT_SOAK_RESTART_SECONDS=${toString soakRestartSeconds} \
      ANVIL_PERSISTENT_SOAK_READINESS_SECONDS=${toString soakReadinessSeconds} \
      ANVIL_SMOKE_WATCHDOG_NORMAL_SECONDS=${toString anvilMcp.timeoutPolicy.watchdogHeartbeatSeconds} \
      ANVIL_SMOKE_WATCHDOG_DISPATCH_SECONDS=${toString anvilMcp.timeoutPolicy.watchdogDispatchSeconds} \
      ${coreutils}/bin/timeout --signal=TERM --kill-after=60 ${toString soakTimeoutSeconds} \
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
