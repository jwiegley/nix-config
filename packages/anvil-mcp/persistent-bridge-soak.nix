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
  soakBridgeCount = 2;
  # The 25-cycle subprocess derives to a 160m38s TERM deadline and a 161m58s
  # absolute SIGKILL horizon.  Keep a nearby finite ceiling without reducing
  # any recovery cycle, nested call bound, named phase, or process margin.
  soakKillAfterSeconds = 80;
  soakProcessHardCeilingSeconds = 162 * 60;
  soakFocusedTimeoutSeconds = 420;
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
  soakNonceStartBudgetSeconds = 10;
  soakHealthySeconds = watchdogWindowSeconds - soakNonceStartBudgetSeconds;
  soakRestartSeconds = 2 * policy.bridgeReadinessSeconds;
  soakReadinessSeconds = watchdogWindowSeconds;
  soakFixtureCommandCount = 4;
  soakLocalCommandSeconds = 30;
  soakInstanceDiscoverySeconds = 150;
  soakToolsListSeconds = 60;
  soakToolCallSeconds = 10;
  soakAsyncSubmissionSeconds = 30;
  soakAsyncCompatibilityPollSeconds = 45;
  soakAsyncProjectPollSeconds = 25;
  soakAsyncMarkerSeconds = 15;
  soakAsyncMarkerSchedulingGraceSeconds = 5;
  soakAsyncPulseSeconds = 3;
  soakAsyncResultPublicationGraceSeconds = 5;
  soakAsyncLoopJobSeconds =
    soakAsyncSubmissionSeconds
    + soakAsyncMarkerSeconds
    + soakToolCallSeconds
    + soakAsyncPulseSeconds
    + soakAsyncMarkerSchedulingGraceSeconds;
  soakAsyncLoopSettleSeconds = soakAsyncLoopJobSeconds + soakAsyncResultPublicationGraceSeconds;
  soakAsyncRecoveredSettleSeconds = soakAsyncMarkerSeconds + soakAsyncProjectPollSeconds;
  soakAsyncChildExitSeconds = 10;
  soakWorkerInventorySeconds = 110;
  soakProcessSnapshotSeconds = 30;
  soakSetupSchedulingGraceSeconds = 40;
  soakInventorySchedulingGraceSeconds = 30;
  soakYieldingResponseSeconds = 50 + watchdogResponseGraceSeconds;
  soakAsyncChildIsolationSeconds =
    soakAsyncSubmissionSeconds + soakAsyncRecoveredSettleSeconds + soakAsyncChildExitSeconds;
  soakAsyncIsolationSeconds =
    soakAsyncSubmissionSeconds
    + soakAsyncCompatibilityPollSeconds
    + soakAsyncSubmissionSeconds
    + soakAsyncProjectPollSeconds
    + soakAsyncSubmissionSeconds
    + soakAsyncLoopSettleSeconds
    + soakAsyncChildExitSeconds;
  soakWarmBridgeSeconds = soakToolsListSeconds + 3 * soakToolCallSeconds + policy.clientToolSeconds;
  soakCycleBudgetSeconds =
    watchdogResponseBudgetSeconds
    + soakRestartSeconds
    + policy.bridgeReadinessSeconds
    + soakReadinessSeconds
    + policy.frameReadSeconds;

  # Fixed work is split into enforced phases rather than an opaque allowance.
  # Setup and inventory add every sequential nested timeout plus explicit
  # scheduling grace.  Post-recovery inventory proves successful child
  # offload isolation on each recovered bridge before worker/process custody.
  soakSetupSeconds =
    soakFixtureCommandCount * soakLocalCommandSeconds
    +
      soakBridgeCount
      * (
        policy.clientStartupSeconds
        + soakInstanceDiscoverySeconds
        + soakWarmBridgeSeconds
        + soakAsyncIsolationSeconds
      )
    + soakToolCallSeconds
    + soakYieldingResponseSeconds
    + soakSetupSchedulingGraceSeconds;
  soakInventorySeconds =
    soakBridgeCount
    * (soakAsyncChildIsolationSeconds + soakWorkerInventorySeconds + soakProcessSnapshotSeconds)
    + soakInventorySchedulingGraceSeconds;
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
assert soakCycles >= 25;
assert soakMarginPercent >= 20;
assert soakKillAfterSeconds > 0;
assert soakKillAfterSeconds > soakBridgeCleanupSeconds;
assert soakHealthySeconds > 0;
assert soakNonceStartBudgetSeconds + soakHealthySeconds <= watchdogWindowSeconds;
assert soakMarginSeconds * 100 >= soakInternalBudgetSeconds * soakMarginPercent;
assert soakTimeoutSeconds > soakInternalBudgetSeconds;
assert soakTimeoutSeconds + soakKillAfterSeconds <= soakProcessHardCeilingSeconds;
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
      nonceStartSeconds = soakNonceStartBudgetSeconds;
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
      killAfterSeconds = soakKillAfterSeconds;
      hardCeilingSeconds = soakProcessHardCeilingSeconds;
      focusedTimeoutSeconds = soakFocusedTimeoutSeconds;
    };
  }
  ''
    ${coreutils}/bin/timeout --signal=TERM --kill-after=${toString soakKillAfterSeconds} ${toString soakFocusedTimeoutSeconds} \
      ${coreutils}/bin/env \
      ANVIL_MCP_CLIENT_STARTUP_SECONDS=${toString policy.clientStartupSeconds} \
      ANVIL_MCP_CLIENT_TOOL_SECONDS=${toString policy.clientToolSeconds} \
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
      ${toString soakTimeoutSeconds} \
      ${toString soakKillAfterSeconds} \
      ${toString soakProcessHardCeilingSeconds}

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
      ANVIL_MCP_CLIENT_STARTUP_SECONDS=${toString policy.clientStartupSeconds} \
      ANVIL_MCP_CLIENT_TOOL_SECONDS=${toString policy.clientToolSeconds} \
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
      ${coreutils}/bin/timeout --signal=TERM --kill-after=${toString soakKillAfterSeconds} ${toString soakTimeoutSeconds} \
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
