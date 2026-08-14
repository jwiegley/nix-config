{
  bootstrapCommand,
  desktopDirectory,
  desktopIgnoreFile,
  documentsDirectory,
  documentsIgnoreFile,
  guiSocket,
  lib,
  localDeviceID,
  logDirectory,
  runtimeDirectory,
  stateDirectory,
  tools,
  username,
}:

let
  quote = lib.escapeShellArg;
in
''
  syncthing_fail() {
    echo "syncthing preflight: $1" >&2
    exit 1
  }
  syncthing_require_directory() {
    local path="$1" expected_mode="$2"
    [[ -d "$path" && ! -L "$path" ]] \
      || syncthing_fail "required private directory is missing or unsafe: $path"
    [[ "$(${tools.stat} -f '%Su' "$path")" == ${quote username} ]] \
      || syncthing_fail "private directory has the wrong owner: $path"
    [[ "$(${tools.stat} -f '%Lp' "$path")" == "$expected_mode" ]] \
      || syncthing_fail "private directory has the wrong mode: $path"
  }
  syncthing_require_file() {
    local path="$1"
    [[ -f "$path" && ! -L "$path" ]] \
      || syncthing_fail "required private file is missing or unsafe: $path"
    [[ "$(${tools.stat} -f '%Su' "$path")" == ${quote username} ]] \
      || syncthing_fail "private file has the wrong owner: $path"
    [[ "$(${tools.stat} -f '%Lp' "$path")" == "600" ]] \
      || syncthing_fail "private file has the wrong mode: $path"
  }
  syncthing_prepare_directory() {
    local path="$1"
    if [[ -e "$path" || -L "$path" ]]; then
      [[ -d "$path" && ! -L "$path" ]] \
        || syncthing_fail "required private directory is missing or unsafe: $path"
    fi
    ${tools.install} -d -m 0700 "$path" \
      || syncthing_fail "could not create private directory: $path"
    syncthing_require_directory "$path" 700
  }

  syncthing_prepare_directory ${quote logDirectory}
  syncthing_prepare_directory ${quote runtimeDirectory}
  syncthing_require_directory ${quote stateDirectory} 700
  syncthing_require_directory ${quote documentsDirectory} 700
  syncthing_require_directory ${quote desktopDirectory} 700
  syncthing_require_file ${quote "${stateDirectory}/cert.pem"}
  syncthing_require_file ${quote "${stateDirectory}/key.pem"}
  syncthing_require_file ${quote "${stateDirectory}/config.xml"}

  actual_device_id="$(${tools.syncthing} device-id --home ${quote stateDirectory} 2>/dev/null)" \
    || syncthing_fail "could not derive the bootstrapped device identity"
  [[ "$actual_device_id" == ${quote localDeviceID} ]] \
    || syncthing_fail "bootstrapped device identity does not match this host"

  login_items_status=0
  (
    set -e
    login_items=${quote "${runtimeDirectory}/login-items"}.$$
    trap '${tools.rm} -f "$login_items"' EXIT
    ${tools.install} -m 0600 /dev/null "$login_items" || exit 10
    ${tools.sfltool} list com.apple.LSSharedFileList.SessionLoginItems >"$login_items" 2>&1 &
    login_items_pid=$!
    login_items_done=0
    for ((attempt = 0; attempt < 50; attempt++)); do
      if ! ${tools.kill} -0 "$login_items_pid" 2>/dev/null; then
        if wait "$login_items_pid"; then
          login_items_done=1
        fi
        break
      fi
      ${tools.sleep} 0.1
    done
    if [[ "$login_items_done" == 0 ]]; then
      ${tools.kill} "$login_items_pid" 2>/dev/null || true
      wait "$login_items_pid" 2>/dev/null || true
      exit 10
    fi
    login_items_match_status=0
    ${tools.grep} -Eiq '(/Applications/Syncthing\.app|com\.github\.xor-gate\.syncthing-macosx)' "$login_items" \
      || login_items_match_status=$?
    case "$login_items_match_status" in
      0) exit 20 ;;
      1) ;;
      *) exit 10 ;;
    esac
  ) || login_items_status=$?
  case "$login_items_status" in
    0) ;;
    20) syncthing_fail "Syncthing.app is still registered as a login item" ;;
    *) syncthing_fail "could not safely inspect legacy login items" ;;
  esac

  daemon_pids=( )
  for ((attempt = 0; attempt < 20; attempt++)); do
    daemon_output=""
    daemon_status=0
    daemon_output="$(${tools.pgrep} -x syncthing 2>/dev/null)" || daemon_status=$?
    case "$daemon_status" in
      0) mapfile -t daemon_pids <<<"$daemon_output" ;;
      1) daemon_pids=( ) ;;
      *) syncthing_fail "could not safely inspect running Syncthing processes" ;;
    esac
    (( ''${#daemon_pids[@]} != 1 )) && break
    ${tools.sleep} 0.1
  done
  daemon_running=0
  if (( ''${#daemon_pids[@]} > 0 )); then
    managed_pid="$(${tools.launchctl} print gui/$(${tools.id} -u)/org.nix-community.home.syncthing 2>/dev/null \
      | ${tools.awk} '/^[[:space:]]*pid = / { print $3; exit }')"
    [[ -n "$managed_pid" && ''${#daemon_pids[@]} == 2 ]] \
      || syncthing_fail "an unmanaged, duplicate, or unhealthy Syncthing instance is running"
    if [[ "''${daemon_pids[0]}" == "$managed_pid" ]]; then
      child_pid="''${daemon_pids[1]}"
    elif [[ "''${daemon_pids[1]}" == "$managed_pid" ]]; then
      child_pid="''${daemon_pids[0]}"
    else
      syncthing_fail "the Syncthing monitor is not owned by the managed launchd job"
    fi
    child_parent="$(${tools.ps} -p "$child_pid" -o ppid= | ${tools.tr} -d ' ')"
    [[ "$child_parent" == "$managed_pid" ]] \
      || syncthing_fail "the second Syncthing process is not the managed monitor child"
    daemon_running=1
  fi

  if [[ -L ${quote "${documentsDirectory}/.stignore"} ]] \
    || { [[ -e ${quote "${documentsDirectory}/.stignore"} ]] \
      && [[ ! -f ${quote "${documentsDirectory}/.stignore"} ]]; }; then
    syncthing_fail "Documents .stignore is not a safe regular file"
  fi
  if ! ${tools.cmp} -s ${documentsIgnoreFile} ${quote "${documentsDirectory}/.stignore"} \
    || [[ "$(${tools.stat} -f '%Su' ${quote "${documentsDirectory}/.stignore"})" != ${quote username} ]] \
    || [[ "$(${tools.stat} -f '%Lp' ${quote "${documentsDirectory}/.stignore"})" != 600 ]]; then
    (
      set -e
      ignore_tmp=${quote "${documentsDirectory}/.stignore.tmp"}.$$
      trap '${tools.rm} -f "$ignore_tmp"' EXIT
      ${tools.install} -m 0600 ${documentsIgnoreFile} "$ignore_tmp"
      ${tools.mv} -f "$ignore_tmp" ${quote "${documentsDirectory}/.stignore"}
    ) || syncthing_fail "could not install the managed Documents .stignore"
  fi

  if [[ -L ${quote "${desktopDirectory}/.stignore"} ]] \
    || { [[ -e ${quote "${desktopDirectory}/.stignore"} ]] \
      && [[ ! -f ${quote "${desktopDirectory}/.stignore"} ]]; }; then
    syncthing_fail "Desktop .stignore is not a safe regular file"
  fi
  if ! ${tools.cmp} -s ${desktopIgnoreFile} ${quote "${desktopDirectory}/.stignore"} \
    || [[ "$(${tools.stat} -f '%Su' ${quote "${desktopDirectory}/.stignore"})" != ${quote username} ]] \
    || [[ "$(${tools.stat} -f '%Lp' ${quote "${desktopDirectory}/.stignore"})" != 600 ]]; then
    (
      set -e
      ignore_tmp=${quote "${desktopDirectory}/.stignore.tmp"}.$$
      trap '${tools.rm} -f "$ignore_tmp"' EXIT
      ${tools.install} -m 0600 ${desktopIgnoreFile} "$ignore_tmp"
      ${tools.mv} -f "$ignore_tmp" ${quote "${desktopDirectory}/.stignore"}
    ) || syncthing_fail "could not install the managed Desktop .stignore"
  fi

  syncthing_exclude_from_time_machine() {
    local path="$1" excluded
    excluded="$(
      ${tools.tmutil} isexcluded -X "$path" \
        | ${tools.plutil} -extract 0.IsExcluded raw -o - -- -
    )" || syncthing_fail "could not inspect Time Machine exclusion"
    if [[ "$excluded" != 1 ]]; then
      ${tools.tmutil} addexclusion "$path" \
        || syncthing_fail "could not add Time Machine exclusion"
    fi
  }
  syncthing_exclude_from_time_machine ${quote documentsDirectory}
  syncthing_exclude_from_time_machine ${quote desktopDirectory}

  if [[ -e ${quote guiSocket} || -L ${quote guiSocket} ]]; then
    [[ -S ${quote guiSocket} && ! -L ${quote guiSocket} ]] \
      || syncthing_fail "GUI socket path is unsafe"
    if [[ "$daemon_running" == 0 ]]; then
      ${tools.rm} -f ${quote guiSocket}
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
''
