{
  classicFixtures,
  classicPackage,
  coreutils,
  nodejs_24,
  writeShellApplication,
}:

writeShellApplication {
  name = "pi-classic-core-baseline";
  runtimeInputs = [ coreutils ];
  text = ''
    # Consequential failures are captured explicitly so the runner can retain evidence.
    set +e
    set -uo pipefail
    umask 077

    if [[ $# -ne 1 ]]; then
      echo "usage: pi-classic-core-baseline /private/tmp/NEW-BUNDLE-NAME" >&2
      exit 64
    fi

    requested_path=$1
    case "$requested_path" in
      *$'\n'* | *$'\r'*)
        echo "bundle path must not contain CR or LF" >&2
        exit 64
        ;;
      /*) ;;
      *)
        echo "bundle path must be absolute: $requested_path" >&2
        exit 64
        ;;
    esac

    if ! bundle_name=$(${coreutils}/bin/basename -- "$requested_path"); then
      echo "could not determine bundle basename" >&2
      exit 64
    fi
    case "$bundle_name" in
      "" | "." | ".." | */*)
        echo "bundle path has an invalid basename" >&2
        exit 64
        ;;
    esac

    if ! requested_parent=$(${coreutils}/bin/dirname -- "$requested_path"); then
      echo "could not determine bundle parent" >&2
      exit 73
    fi
    if [[ ! -d "$requested_parent" || -L "$requested_parent" ]]; then
      echo "bundle parent must be an existing physical directory: $requested_parent" >&2
      exit 73
    fi
    if ! bundle_parent_marked=$(cd -P -- "$requested_parent" && printf '%s.' "$PWD"); then
      echo "could not resolve bundle parent physically: $requested_parent" >&2
      exit 73
    fi
    bundle_parent=''${bundle_parent_marked%.}
    case "$bundle_parent" in
      "" | *$'\n'* | *$'\r'*)
        echo "physical bundle parent is invalid" >&2
        exit 73
        ;;
      /*) ;;
      *)
        echo "physical bundle parent is not absolute" >&2
        exit 73
        ;;
    esac

    trusted_bundle_parent() {
      [[
        "$bundle_parent" == /private/tmp
        && -d /private
        && ! -L /private
        && -d /private/tmp
        && ! -L /private/tmp
        && "$(${coreutils}/bin/stat --format='%u:%a' -- /private 2>/dev/null)" == 0:755
        && "$(${coreutils}/bin/stat --format='%u:%a' -- /private/tmp 2>/dev/null)" == 0:1777
      ]]
    }

    # Later publication reopens this path, so accept only macOS' fixed,
    # root-owned sticky temporary directory. Other UIDs cannot replace its
    # ancestors or this runner's entries; hostile same-UID mutation is outside
    # the shell runner's achievable threat model.
    if ! trusted_bundle_parent; then
      echo "bundle parent must be the trusted physical directory /private/tmp" >&2
      exit 73
    fi

    bundle_path="$bundle_parent/$bundle_name"
    if [[ -e "$bundle_path" || -L "$bundle_path" ]]; then
      echo "bundle path already exists: $bundle_path" >&2
      exit 73
    fi

    work_root=
    work_root_valid=0
    bundle=
    bundle_sealed=0
    published=0
    signal_status=0
    signal_name=
    signal_count=0
    last_signal_name=
    signal_accounting_open=1
    late_signal_status=0
    late_signal_name=
    active_runner_pid=
    forwarded_signal_count=0
    prefinalization_failure=0

    on_exit() {
      local status=$?
      local entry
      local sealed_only=0
      trap - EXIT
      trap - HUP INT TERM
      if [[ $status -eq 0 ]]; then
        if [[ $late_signal_status -ne 0 ]]; then
          status=$late_signal_status
        elif [[ $signal_status -ne 0 ]]; then
          status=$signal_status
        fi
      fi
      if [[ $work_root_valid -eq 1 && -n "$work_root" && ( -e "$work_root" || -L "$work_root" ) ]]; then
        if [[ $published -eq 1 ]]; then
          echo "private post-publication work root retained at $work_root" >&2
        elif [[
          $bundle_sealed -eq 1
          && -n "$bundle"
          && -d "$bundle"
          && ! -L "$bundle"
        ]]; then
          sealed_only=1
          for entry in "$work_root"/* "$work_root"/.[!.]* "$work_root"/..?*; do
            if [[ ( -e "$entry" || -L "$entry" ) && "$entry" != "$bundle" ]]; then
              sealed_only=0
            fi
          done
          if [[ $sealed_only -eq 1 ]]; then
            echo "private sealed-only recovery root retained at $work_root" >&2
          else
            echo "private mixed recovery root retained at $work_root" >&2
          fi
        else
          echo "private mixed recovery root retained at $work_root" >&2
        fi
      fi
      exit "$status"
    }

    forward_runner_signals() {
      local runner_pid
      runner_pid=$(jobs -p)
      if [[ -z "$active_runner_pid" || "$runner_pid" != "$active_runner_pid" ]]; then
        return
      fi
      if [[ $forwarded_signal_count -eq 0 && $signal_count -gt 0 ]]; then
        if ! kill -s "$signal_name" -- "-$active_runner_pid" 2>/dev/null; then
          return
        fi
        forwarded_signal_count=1
        kill -s CONT -- "-$active_runner_pid" 2>/dev/null || true
      fi
      if [[ $forwarded_signal_count -lt $signal_count && $signal_count -gt 1 ]]; then
        if ! kill -s "$last_signal_name" -- "-$active_runner_pid" 2>/dev/null; then
          return
        fi
        forwarded_signal_count=$signal_count
        kill -s CONT -- "-$active_runner_pid" 2>/dev/null || true
      fi
    }

    handle_signal() {
      local name=$1
      local status=$2
      if [[ $signal_accounting_open -eq 0 ]]; then
        if [[ $late_signal_status -eq 0 ]]; then
          late_signal_name=$name
          late_signal_status=$status
        fi
        echo "received $name after signal-accounting cutoff; finalization will fail" >&2
        return
      fi
      signal_count=$((signal_count + 1))
      last_signal_name=$name
      if [[ $signal_status -eq 0 ]]; then
        signal_name=$name
        signal_status=$status
        echo "received $name; finishing failure evidence" >&2
      else
        echo "received repeated $name; failure evidence collection continues" >&2
      fi
      # A repeat reaches the wrapper too; it escalates by killing its child
      # while still recording bounded output.
      forward_runner_signals
    }

    trap on_exit EXIT
    trap 'handle_signal HUP 129' HUP
    trap 'handle_signal INT 130' INT
    trap 'handle_signal TERM 143' TERM

    if ! work_root=$(${coreutils}/bin/mktemp -d "$bundle_parent/.pi-b1-baseline.XXXXXX"); then
      echo "could not create private baseline work root" >&2
      if [[ -n "$work_root" ]]; then
        echo "possible private mixed recovery root retained at $work_root" >&2
      fi
      exit 73
    fi
    case "$work_root" in
      "$bundle_parent"/.pi-b1-baseline.*) ;;
      *)
        echo "possible private mixed recovery root retained at $work_root" >&2
        exit 73
        ;;
    esac
    if [[ ! -d "$work_root" || -L "$work_root" ]]; then
      echo "possible private mixed recovery root retained at $work_root" >&2
      exit 73
    fi
    work_root_valid=1
    bundle="$work_root/bundle"
    if ! ${coreutils}/bin/chmod 0700 -- "$work_root"; then
      echo "could not make baseline work root private" >&2
      exit 73
    fi

    if ! ${coreutils}/bin/mkdir -p \
      "$bundle/identity" \
      "$bundle/protocol" \
      "$bundle/attempt-0001" \
      || ! ${coreutils}/bin/cp \
        "${classicPackage}/b1-source-identity.json" \
        "$bundle/identity/source.json" \
      || ! ${coreutils}/bin/cp \
        "${classicPackage}/b1-source-crosswalk.json" \
        "$bundle/identity/source-to-runtime-crosswalk.json" \
      || ! ${coreutils}/bin/cp \
        "${classicPackage}/empty-extensions.json" \
        "$bundle/identity/empty-extensions.json" \
      || ! ${coreutils}/bin/cp \
        "${classicFixtures}/SHA256SUMS" \
        "$bundle/identity/fixture-SHA256SUMS" \
      || ! ${coreutils}/bin/cp \
        "${classicFixtures}/fixtures/manifest.json" \
        "$bundle/protocol/fixture-manifest.json" \
      || ! ${coreutils}/bin/cp \
        "${classicFixtures}/fixtures/expected-oracles.json" \
        "$bundle/protocol/expected-oracles.json" \
      || ! ${coreutils}/bin/cp "$0" "$bundle/protocol/runner.sh"; then
      echo "baseline initialization failed" >&2
      exit 1
    fi

    evidence_node() {
      ${coreutils}/bin/env -i \
        LC_ALL=C \
        TZ=UTC \
        ${nodejs_24}/bin/node "$@"
    }

    endpoint_note() {
      local endpoint_dir=$1
      local note=$2
      if ! printf '%s\n' "$note" >> "$endpoint_dir/runner-errors.log"; then
        echo "could not record endpoint evidence" >&2
        prefinalization_failure=1
      fi
    }

    endpoint_status() {
      local endpoint_dir=$1
      local setup=$2
      local run=$3
      local postflight=$4
      local cleanup=$5
      if ! printf \
        'setup_status=%s\nrun_status=%s\npostflight_status=%s\ncleanup_status=%s\n' \
        "$setup" "$run" "$postflight" "$cleanup" \
        > "$endpoint_dir/endpoint-status.txt"; then
        echo "could not record endpoint status" >&2
        prefinalization_failure=1
      fi
    }

    cleanup_endpoint_root() {
      local lane=$1
      local root=$2
      local status=0

      if [[ -z "$root" ]]; then
        echo "refusing empty endpoint cleanup root" >&2
        return 1
      fi
      case "$root" in
        "$work_root"/namespace-"$lane".*) ;;
        *)
          echo "refusing unexpected endpoint cleanup root" >&2
          return 1
          ;;
      esac
      if [[ -L "$root" || ! -d "$root" ]]; then
        echo "refusing non-physical endpoint cleanup root" >&2
        return 1
      fi
      ${coreutils}/bin/chmod -R u+rwX -- "$root" || status=1
      ${coreutils}/bin/rm -rf -- "$root" || status=1
      if [[ -e "$root" || -L "$root" ]]; then
        status=1
      fi
      return "$status"
    }

    run_endpoint() {
      local lane=$1
      local scale=$2
      local endpoint_dir
      local private_root=
      local setup_status=0
      local run_status=0
      local postflight_status=0
      local cleanup_status=0

      case "$lane:$scale" in
        low:16m | high:1g) ;;
        *)
          echo "refusing unknown endpoint: $lane:$scale" >&2
          return 64
          ;;
      esac
      endpoint_dir="$bundle/attempt-0001/$lane"
      if ! ${coreutils}/bin/mkdir -p -- "$endpoint_dir"; then
        prefinalization_failure=1
        return 1
      fi
      if [[ $signal_status -ne 0 ]]; then
        endpoint_note "$endpoint_dir" "endpoint skipped after $signal_name"
        endpoint_status "$endpoint_dir" 0 "$signal_status" "$signal_status" 0
        return "$signal_status"
      fi

      if ! private_root=$(${coreutils}/bin/mktemp -d "$work_root/namespace-$lane.XXXXXX"); then
        endpoint_note "$endpoint_dir" "endpoint namespace creation failed"
        if [[ -n "$private_root" ]]; then
          prefinalization_failure=1
          endpoint_status "$endpoint_dir" 1 1 1 1
        else
          endpoint_status "$endpoint_dir" 1 1 1 0
        fi
        return 1
      fi
      case "$private_root" in
        "$work_root"/namespace-"$lane".*) ;;
        *)
          endpoint_note "$endpoint_dir" "endpoint namespace validation failed"
          endpoint_status "$endpoint_dir" 1 1 1 1
          prefinalization_failure=1
          return 1
          ;;
      esac
      if [[ ! -d "$private_root" || -L "$private_root" ]]; then
        endpoint_note "$endpoint_dir" "endpoint namespace is not physical"
        endpoint_status "$endpoint_dir" 1 1 1 1
        prefinalization_failure=1
        return 1
      fi

      if ! ${coreutils}/bin/chmod 0700 -- "$private_root"; then
        setup_status=1
      elif ! ${coreutils}/bin/mkdir -p \
        "$private_root/home" \
        "$private_root/pi-agent" \
        "$private_root/sessions" \
        "$private_root/store" \
        "$private_root/tmp" \
        "$private_root/work" \
        "$private_root/xdg/cache" \
        "$private_root/xdg/config" \
        "$private_root/xdg/data"; then
        setup_status=1
      elif ! ${coreutils}/bin/cp --reflink=never \
        "${classicFixtures}/fixtures/pi-b1-$scale.jsonl" \
        "$private_root/store/session.jsonl"; then
        setup_status=1
      elif ! ${coreutils}/bin/chmod 0600 -- "$private_root/store/session.jsonl"; then
        setup_status=1
      fi
      if [[ $setup_status -ne 0 ]]; then
        endpoint_note "$endpoint_dir" "endpoint setup or fixture copy failed"
        run_status=1
        postflight_status=1
      elif [[ $signal_status -ne 0 ]]; then
        endpoint_note "$endpoint_dir" "endpoint skipped after $signal_name"
        run_status=$signal_status
        postflight_status=$signal_status
      else
        # Job control is scoped to the asynchronous runner so only it gets a
        # dedicated process group; restore the default before postflight work.
        set -m
        (
          if ! cd -- "$private_root/work"; then
            exit 70
          fi
          exec ${coreutils}/bin/env -i \
            HOME="$private_root/home" \
            PI_CODING_AGENT_DIR="$private_root/pi-agent" \
            PI_CODING_AGENT_SESSION_DIR="$private_root/sessions" \
            PI_OFFLINE=1 \
            PI_TELEMETRY=0 \
            XDG_CACHE_HOME="$private_root/xdg/cache" \
            XDG_CONFIG_HOME="$private_root/xdg/config" \
            XDG_DATA_HOME="$private_root/xdg/data" \
            TMPDIR="$private_root/tmp" \
            LC_ALL=C \
            TZ=UTC \
            ${nodejs_24}/bin/node \
              ${classicFixtures}/tools/run-capped-command.mjs \
              --stdout "$endpoint_dir/result.json" \
              --stderr "$endpoint_dir/stderr.log" \
              --run-result "$endpoint_dir/run-result.json" \
              --max-bytes 16777216 \
              -- \
              ${nodejs_24}/bin/node \
                --expose-gc \
                --max-old-space-size=8192 \
                ${classicFixtures}/tools/classic-core-diagnostic.mjs \
                --package-root ${classicPackage} \
                --fixture "$private_root/store/session.jsonl" \
                --manifest ${classicFixtures}/fixtures/manifest.json \
                --oracles ${classicFixtures}/fixtures/expected-oracles.json \
                --extension-manifest ${classicPackage}/empty-extensions.json \
                --endpoint "$scale"
        ) &
        active_runner_pid=$!
        forward_runner_signals
        while true; do
          wait -f "$active_runner_pid"
          run_status=$?
          if [[ "$(jobs -p)" != "$active_runner_pid" ]]; then
            break
          fi
        done
        active_runner_pid=
        set +m
        if [[ $run_status -ne 0 ]]; then
          endpoint_note "$endpoint_dir" "endpoint diagnostic failed with status $run_status"
        fi

        if evidence_node \
          ${classicFixtures}/tools/record-postflight.mjs \
          --fixture "$private_root/store/session.jsonl" \
          --result "$endpoint_dir/result.json" \
          --run-result "$endpoint_dir/run-result.json" \
          --oracles ${classicFixtures}/fixtures/expected-oracles.json \
          --endpoint "$scale" \
          --copy-executable ${coreutils}/bin/cp \
          --output "$endpoint_dir/postflight.json"; then
          postflight_status=0
        else
          postflight_status=$?
          endpoint_note "$endpoint_dir" "endpoint postflight failed with status $postflight_status"
        fi
      fi

      if cleanup_endpoint_root "$lane" "$private_root"; then
        cleanup_status=0
      else
        cleanup_status=$?
        prefinalization_failure=1
        endpoint_note "$endpoint_dir" "endpoint cleanup failed"
      fi
      endpoint_status \
        "$endpoint_dir" \
        "$setup_status" \
        "$run_status" \
        "$postflight_status" \
        "$cleanup_status"

      if [[ $setup_status -ne 0 ]]; then
        return "$setup_status"
      elif [[ $run_status -ne 0 ]]; then
        return "$run_status"
      elif [[ $postflight_status -ne 0 ]]; then
        return "$postflight_status"
      elif [[ $cleanup_status -ne 0 ]]; then
        return "$cleanup_status"
      elif [[ $signal_status -ne 0 ]]; then
        return "$signal_status"
      fi
      return 0
    }

    if run_endpoint low 16m; then
      low_status=0
    else
      low_status=$?
    fi
    if run_endpoint high 1g; then
      high_status=0
    else
      high_status=$?
    fi

    if evidence_node \
      ${classicFixtures}/tools/summarize-diagnostic.mjs \
      --low "$bundle/attempt-0001/low/result.json" \
      --low-postflight "$bundle/attempt-0001/low/postflight.json" \
      --high "$bundle/attempt-0001/high/result.json" \
      --high-postflight "$bundle/attempt-0001/high/postflight.json" \
      --output "$bundle/attempt-0001/summary.json"; then
      summary_status=0
    else
      summary_status=$?
      echo "baseline summary failed with status $summary_status" >&2
    fi

    signal_accounting_open=0
    if ! printf \
      'low_status=%s\nhigh_status=%s\nsummary_status=%s\nsignal_status=%s\nsignal_name=%s\nsignal_count=%s\nlast_signal_name=%s\nsignal_accounting_cutoff=before-seal\n' \
      "$low_status" "$high_status" "$summary_status" "$signal_status" "$signal_name" \
      "$signal_count" "$last_signal_name" \
      > "$bundle/attempt-0001/runner-status.txt"; then
      prefinalization_failure=1
    fi
    if [[ $prefinalization_failure -ne 0 ]]; then
      echo "baseline prefinalization failed; retaining private mixed recovery evidence" >&2
      exit 1
    fi

    if ! evidence_node \
      ${classicFixtures}/tools/seal-bundle.mjs \
      --root "$bundle"; then
      echo "baseline seal failed; retaining private mixed recovery evidence" >&2
      exit 1
    fi
    if [[ ! -f "$bundle/SHA256SUMS" || -L "$bundle/SHA256SUMS" ]]; then
      echo "baseline seal did not create a regular SHA256SUMS" >&2
      exit 1
    fi
    bundle_sealed=1

    unexpected_work_entry=0
    for entry in "$work_root"/* "$work_root"/.[!.]* "$work_root"/..?*; do
      if [[ ! -e "$entry" && ! -L "$entry" ]]; then
        continue
      fi
      if [[ "$entry" != "$bundle" ]]; then
        unexpected_work_entry=1
      fi
    done
    if [[ $unexpected_work_entry -ne 0 ]]; then
      echo "private endpoint state remains before publication" >&2
      exit 1
    fi

    if [[ -e "$bundle_path" || -L "$bundle_path" ]]; then
      echo "bundle path appeared before publication: $bundle_path" >&2
      exit 73
    fi
    if ! trusted_bundle_parent; then
      echo "trusted bundle parent changed before publication" >&2
      exit 73
    fi
    ${coreutils}/bin/mv -T --no-clobber -- "$bundle" "$bundle_path"
    publication_status=$?
    if [[ -e "$bundle" || -L "$bundle" ]]; then
      echo "baseline publication did not move the sealed source bundle" >&2
      exit 73
    fi
    published=1
    # GNU mv's no-clobber fallback on Darwin requires write access to the
    # source directory. Make the exclusively published bundle read-only only
    # after the exclusive move succeeds.
    if ! ${coreutils}/bin/chmod -R a-w -- "$bundle_path"; then
      echo "published sealed bundle could not be made read-only: $bundle_path" >&2
      exit 1
    fi

    if ! ${coreutils}/bin/rmdir -- "$work_root"; then
      echo "published baseline, but private work root was not empty: $work_root" >&2
      exit 1
    fi
    work_root=
    work_root_valid=0

    if [[ $publication_status -ne 0 ]]; then
      echo "B1 diagnostic publication reported status $publication_status; sealed evidence is at $bundle_path" >&2
      exit 1
    fi
    if [[ $late_signal_status -ne 0 ]]; then
      echo "B1 diagnostic interrupted late by $late_signal_name; sealed evidence retained at $bundle_path" >&2
      exit "$late_signal_status"
    fi
    if [[ $signal_status -ne 0 ]]; then
      echo "B1 diagnostic interrupted by $signal_name; sealed evidence retained at $bundle_path" >&2
      exit "$signal_status"
    fi
    if [[ $low_status -ne 0 || $high_status -ne 0 || $summary_status -ne 0 ]]; then
      echo "B1 diagnostic failed; sealed evidence retained at $bundle_path" >&2
      exit 1
    fi
    printf '%s\n' "$bundle_path"
  '';
}
