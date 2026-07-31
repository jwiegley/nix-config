{ lib, pkgs }:

{ root }:

let
  sourceRoot = ".pi/agent";
  markerRoot = builtins.dirOf root;
  markerName = ".nix-pi-profile-migrated-v1";
  validRelativePath =
    path:
    let
      parts = lib.splitString "/" path;
    in
    path != ""
    && !(lib.hasPrefix "/" path)
    && builtins.all (part: part != "" && part != "." && part != "..") parts;

  script = ''
    pi_source="$HOME"/${lib.escapeShellArg sourceRoot}
    pi_destination="$HOME"/${lib.escapeShellArg root}
    pi_marker="$HOME"/${lib.escapeShellArg "${markerRoot}/${markerName}"}
    pi_destination_parent="''${pi_destination%/*}"
    pi_destination_backup="$pi_destination_parent/.pi-profile-destination-backup-v1"
    pi_source_resolved=

    pi_fail() {
      printf '%s\n' "Pi profile migration: $1" >&2
      exit 1
    }

    pi_copy_tree() {
      pi_copy_source=$1
      pi_copy_destination=$2
      run ${pkgs.coreutils}/bin/cp \
        --archive --no-preserve=links --update=none -- \
        "$pi_copy_source/." "$pi_copy_destination/"
    }

    pi_remove_destination_backup() {
      if [ -L "$pi_destination_backup" ]; then
        run ${pkgs.coreutils}/bin/rm -f -- "$pi_destination_backup"
      elif [ -d "$pi_destination_backup" ]; then
        run ${pkgs.coreutils}/bin/rm -rf -- "$pi_destination_backup"
      else
        pi_fail "destination backup has an invalid type: $pi_destination_backup"
      fi
    }

    if [ -e "$pi_marker" ] || [ -L "$pi_marker" ]; then
      if [ ! -f "$pi_marker" ] || [ -L "$pi_marker" ]; then
        pi_fail "completion marker is not a regular file: $pi_marker"
      fi
    fi

    pi_recovery_stage=
    pi_recovery_stage_count=0
    for pi_stage_candidate in "$pi_destination_parent"/.pi-profile-migration.*; do
      if [ -L "$pi_stage_candidate" ]; then
        pi_fail "staging path is a symlink: $pi_stage_candidate"
      elif [ -d "$pi_stage_candidate" ]; then
        pi_recovery_stage_count=$((pi_recovery_stage_count + 1))
        pi_recovery_stage=$pi_stage_candidate
      fi
    done

    pi_recovery_ready=
    pi_recovery_ready_count=0
    for pi_ready_candidate in "$pi_destination_parent"/.pi-profile-migration.*.ready; do
      if [ -L "$pi_ready_candidate" ]; then
        pi_fail "staging marker is a symlink: $pi_ready_candidate"
      elif [ -f "$pi_ready_candidate" ]; then
        pi_recovery_ready_count=$((pi_recovery_ready_count + 1))
        pi_recovery_ready=$pi_ready_candidate
      fi
    done

    if [ "$pi_recovery_stage_count" -gt 1 ]; then
      pi_fail "multiple interrupted staging directories require inspection"
    elif [ "$pi_recovery_ready_count" -gt 1 ]; then
      pi_fail "multiple interrupted staging markers require inspection"
    elif [ -n "$pi_recovery_stage" ] && [ -n "$pi_recovery_ready" ] \
      && [ "$pi_recovery_ready" != "$pi_recovery_stage.ready" ]; then
      pi_fail "staging directory and marker do not match"
    fi

    pi_backup_exists=false
    if [ -e "$pi_destination_backup" ] || [ -L "$pi_destination_backup" ]; then
      pi_backup_exists=true
      if [ -L "$pi_destination_backup" ]; then
        pi_backup_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$pi_destination_backup")"
        pi_legacy_parent_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$HOME/.pi")"
        pi_source_candidate_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$pi_source")"
        if [ "$pi_backup_resolved" != "$pi_legacy_parent_resolved" ] \
          && [ "$pi_backup_resolved" != "$pi_source_candidate_resolved" ]; then
          pi_fail "destination backup symlink has an unexpected target: $pi_destination_backup"
        fi
      elif [ ! -d "$pi_destination_backup" ]; then
        pi_fail "destination backup has an invalid type: $pi_destination_backup"
      fi
    fi

    pi_recovered=false
    if [ "$pi_backup_exists" = true ]; then
      if [ ! -e "$pi_destination" ] && [ ! -L "$pi_destination" ]; then
        if [ -n "$pi_recovery_stage" ] \
          && [ "$pi_recovery_ready" = "$pi_recovery_stage.ready" ]; then
          run ${pkgs.coreutils}/bin/mv -T -- "$pi_recovery_stage" "$pi_destination"
          pi_recovery_stage=
          run ${pkgs.coreutils}/bin/touch -- "$pi_marker"
          pi_remove_destination_backup
          pi_backup_exists=false
          run ${pkgs.coreutils}/bin/rm -f -- "$pi_recovery_ready"
          pi_recovery_ready=
          pi_recovered=true
        else
          run ${pkgs.coreutils}/bin/mv -T -- "$pi_destination_backup" "$pi_destination"
          pi_fail "restored the destination after an incomplete migration; inspect the staging state"
        fi
      elif [ -d "$pi_destination" ] && [ ! -L "$pi_destination" ] \
        && [ -z "$pi_recovery_stage" ] && [ -n "$pi_recovery_ready" ]; then
        run ${pkgs.coreutils}/bin/touch -- "$pi_marker"
        pi_remove_destination_backup
        pi_backup_exists=false
        run ${pkgs.coreutils}/bin/rm -f -- "$pi_recovery_ready"
        pi_recovery_ready=
        pi_recovered=true
      elif [ -d "$pi_destination" ] && [ ! -L "$pi_destination" ] \
        && [ -z "$pi_recovery_stage" ] && [ -z "$pi_recovery_ready" ] \
        && [ -f "$pi_marker" ]; then
        pi_remove_destination_backup
        pi_backup_exists=false
        pi_recovered=true
      else
        pi_fail "ambiguous destination backup state requires inspection: $pi_destination_backup"
      fi
    elif [ ! -e "$pi_destination" ] && [ ! -L "$pi_destination" ] \
      && [ -n "$pi_recovery_stage" ] \
      && [ "$pi_recovery_ready" = "$pi_recovery_stage.ready" ]; then
      run ${pkgs.coreutils}/bin/mv -T -- "$pi_recovery_stage" "$pi_destination"
      pi_recovery_stage=
      run ${pkgs.coreutils}/bin/touch -- "$pi_marker"
      run ${pkgs.coreutils}/bin/rm -f -- "$pi_recovery_ready"
      pi_recovery_ready=
      pi_recovered=true
    elif [ -d "$pi_destination" ] && [ ! -L "$pi_destination" ] \
      && [ -z "$pi_recovery_stage" ] && [ -n "$pi_recovery_ready" ]; then
      run ${pkgs.coreutils}/bin/touch -- "$pi_marker"
      run ${pkgs.coreutils}/bin/rm -f -- "$pi_recovery_ready"
      pi_recovery_ready=
      pi_recovered=true
    elif [ -n "$pi_recovery_stage" ] || [ -n "$pi_recovery_ready" ]; then
      pi_fail "interrupted staging state requires inspection"
    fi

    pi_should_migrate=false
    if [ "$pi_recovered" = true ]; then
      pi_should_migrate=false
    elif [ -L "$pi_destination" ]; then
      pi_should_migrate=true
    elif { [ ! -e "$pi_marker" ] && [ ! -L "$pi_marker" ]; } \
      && { [ -e "$pi_source" ] || [ -L "$pi_source" ]; }; then
      pi_should_migrate=true
    fi

    if [ "$pi_should_migrate" = true ]; then
      if [ -e "$pi_source" ] || [ -L "$pi_source" ]; then
        if [ ! -d "$pi_source" ]; then
          pi_fail "source is not a directory: $pi_source"
        fi
        pi_source_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$pi_source")"
      fi

      if [ -e "$pi_destination" ] || [ -L "$pi_destination" ]; then
        if [ ! -d "$pi_destination" ]; then
          pi_fail "destination is not a directory: $pi_destination"
        fi
        if [ -L "$pi_destination" ]; then
          pi_destination_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$pi_destination")"
          pi_legacy_parent_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$HOME/.pi")"
          if [ "$pi_destination_resolved" != "$pi_legacy_parent_resolved" ] \
            && { [ -z "$pi_source_resolved" ] \
              || [ "$pi_destination_resolved" != "$pi_source_resolved" ]; }; then
            pi_fail "destination symlink has an unexpected target: $pi_destination"
          fi
        fi
      fi

      if [[ -v DRY_RUN ]]; then
        printf '%s\n' \
          "Pi profile migration: would stage and install the XDG profile: $pi_destination"
      else
        (
          pi_stage=
          pi_stage_ready=
          pi_backup_moved=false
          pi_cleanup_stage() {
            if [ "$pi_backup_moved" = true ] \
              && { [ -e "$pi_destination_backup" ] || [ -L "$pi_destination_backup" ]; } \
              && [ ! -e "$pi_destination" ] && [ ! -L "$pi_destination" ]; then
              run ${pkgs.coreutils}/bin/mv -T -- \
                "$pi_destination_backup" "$pi_destination"
              pi_backup_moved=false
            fi
            if [ "$pi_backup_moved" = false ]; then
              if [ -n "$pi_stage" ] && [ -d "$pi_stage" ] && [ ! -L "$pi_stage" ]; then
                case "$pi_stage" in
                  "$pi_destination_parent"/.pi-profile-migration.*)
                    run ${pkgs.coreutils}/bin/rm -rf -- "$pi_stage"
                    ;;
                esac
              fi
              if [ -n "$pi_stage_ready" ] && [ -f "$pi_stage_ready" ] \
                && [ ! -L "$pi_stage_ready" ]; then
                run ${pkgs.coreutils}/bin/rm -f -- "$pi_stage_ready"
              fi
            fi
          }
          trap pi_cleanup_stage EXIT
          trap 'exit 129' HUP
          trap 'exit 130' INT
          trap 'exit 143' TERM

          if [ -e "$pi_destination_parent" ] || [ -L "$pi_destination_parent" ]; then
            if [ ! -d "$pi_destination_parent" ]; then
              pi_fail "destination parent is not a directory: $pi_destination_parent"
            fi
          else
            run ${pkgs.coreutils}/bin/mkdir -m 0700 -p -- "$pi_destination_parent"
          fi
          pi_stage="$(${pkgs.coreutils}/bin/mktemp -d \
            "$pi_destination_parent/.pi-profile-migration.XXXXXX")"
          if [ -e "$pi_destination" ] || [ -L "$pi_destination" ]; then
            pi_destination_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$pi_destination")"
            pi_copy_tree "$pi_destination" "$pi_stage"
          else
            pi_destination_resolved=
          fi
          if [ -n "$pi_source_resolved" ] \
            && [ "$pi_source_resolved" != "$pi_destination_resolved" ]; then
            pi_copy_tree "$pi_source" "$pi_stage"
          fi
          if [ -d "$pi_destination" ] && [ ! -L "$pi_destination" ]; then
            run ${pkgs.coreutils}/bin/chmod --reference="$pi_destination" -- "$pi_stage"
          else
            run ${pkgs.coreutils}/bin/chmod 0700 -- "$pi_stage"
          fi
          pi_stage_ready="$pi_stage.ready"
          run ${pkgs.coreutils}/bin/touch -- "$pi_stage_ready"

          if [ -e "$pi_destination" ] || [ -L "$pi_destination" ]; then
            if [ -e "$pi_destination_backup" ] || [ -L "$pi_destination_backup" ]; then
              pi_fail "reserved destination backup already exists: $pi_destination_backup"
            fi
            run ${pkgs.coreutils}/bin/mv -T -- \
              "$pi_destination" "$pi_destination_backup"
            pi_backup_moved=true
          fi
          run ${pkgs.coreutils}/bin/mv -T -- "$pi_stage" "$pi_destination"
          pi_stage=
          run ${pkgs.coreutils}/bin/touch -- "$pi_marker"
          if [ "$pi_backup_moved" = true ]; then
            pi_remove_destination_backup
            pi_backup_moved=false
          fi
          run ${pkgs.coreutils}/bin/rm -f -- "$pi_stage_ready"
          pi_stage_ready=
          trap - EXIT HUP INT TERM
        )
      fi
    fi
  '';
in
assert validRelativePath root;
assert markerRoot != ".";
assert root != sourceRoot;
{
  inherit script;
  activation = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] script;
}
