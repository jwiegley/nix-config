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
    pi_link_backup="$pi_destination_parent/.pi-profile-legacy-link-v1"
    pi_stage_ready_name=.nix-pi-profile-stage-ready-v1
    pi_source_resolved=

    pi_copy_tree() {
      pi_copy_source=$1
      pi_copy_destination=$2
      run ${pkgs.coreutils}/bin/cp \
        --archive --no-preserve=links --update=none -- \
        "$pi_copy_source/." "$pi_copy_destination/"
    }

    pi_recovered=false
    pi_recovery_stage=
    pi_recovery_stage_count=0
    for pi_stage_candidate in "$pi_destination_parent"/.pi-profile-migration.*; do
      [ -d "$pi_stage_candidate" ] || continue
      pi_recovery_stage_count=$((pi_recovery_stage_count + 1))
      pi_recovery_stage=$pi_stage_candidate
    done
    if [ "$pi_recovery_stage_count" -gt 1 ]; then
      printf '%s\n' \
        "Pi profile migration: multiple interrupted staging directories require inspection" >&2
      exit 1
    fi

    if [ -e "$pi_link_backup" ] || [ -L "$pi_link_backup" ]; then
      if [ ! -L "$pi_link_backup" ]; then
        printf '%s\n' \
          "Pi profile migration: rollback path is not a symlink: $pi_link_backup" >&2
        exit 1
      fi
      pi_backup_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$pi_link_backup")"
      pi_legacy_parent_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$HOME/.pi")"
      pi_source_candidate_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$pi_source")"
      if [ "$pi_backup_resolved" != "$pi_legacy_parent_resolved" ] \
        && [ "$pi_backup_resolved" != "$pi_source_candidate_resolved" ]; then
        printf '%s\n' \
          "Pi profile migration: rollback symlink has an unexpected target: $pi_link_backup" >&2
        exit 1
      elif [ ! -e "$pi_destination" ] && [ ! -L "$pi_destination" ]; then
        if [ -n "$pi_recovery_stage" ] \
          && [ -f "$pi_recovery_stage/$pi_stage_ready_name" ]; then
          run ${pkgs.coreutils}/bin/mv -T -- "$pi_recovery_stage" "$pi_destination"
          pi_recovery_stage=
          run ${pkgs.coreutils}/bin/rm -f -- "$pi_link_backup"
          run ${pkgs.coreutils}/bin/rm -f -- "$pi_destination/$pi_stage_ready_name"
          run ${pkgs.coreutils}/bin/touch -- "$pi_marker"
          pi_recovered=true
        else
          run ${pkgs.coreutils}/bin/mv -T -- "$pi_link_backup" "$pi_destination"
          printf '%s\n' \
            "Pi profile migration: restored the legacy link after an incomplete migration; inspect the staging directory" >&2
          exit 1
        fi
      elif [ -d "$pi_destination" ] \
        && [ -f "$pi_destination/$pi_stage_ready_name" ]; then
        run ${pkgs.coreutils}/bin/rm -f -- "$pi_link_backup"
        run ${pkgs.coreutils}/bin/rm -f -- "$pi_destination/$pi_stage_ready_name"
        run ${pkgs.coreutils}/bin/touch -- "$pi_marker"
        pi_recovered=true
      else
        printf '%s\n' \
          "Pi profile migration: ambiguous rollback state requires inspection: $pi_link_backup" >&2
        exit 1
      fi
    elif [ -f "$pi_destination/$pi_stage_ready_name" ]; then
      run ${pkgs.coreutils}/bin/rm -f -- "$pi_destination/$pi_stage_ready_name"
      run ${pkgs.coreutils}/bin/touch -- "$pi_marker"
      pi_recovered=true
    elif [ -n "$pi_recovery_stage" ]; then
      printf '%s\n' \
        "Pi profile migration: interrupted staging directory requires inspection: $pi_recovery_stage" >&2
      exit 1
    fi

    pi_replace_legacy_destination_link() (
      pi_destination_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$pi_destination")"
      pi_legacy_parent_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$HOME/.pi")"

      if [ "$pi_destination_resolved" != "$pi_legacy_parent_resolved" ] \
        && { [ -z "$pi_source_resolved" ] \
          || [ "$pi_destination_resolved" != "$pi_source_resolved" ]; }; then
        printf '%s\n' \
          "Pi profile migration: destination symlink has an unexpected target: $pi_destination" >&2
        exit 1
      fi

      if [[ -v DRY_RUN ]]; then
        printf '%s\n' \
          "Pi profile migration: would replace legacy destination symlink: $pi_destination"
        exit 0
      fi

      pi_stage=
      pi_link_moved=false
      if [ -e "$pi_link_backup" ] || [ -L "$pi_link_backup" ]; then
        printf '%s\n' \
          "Pi profile migration: reserved rollback path already exists: $pi_link_backup" >&2
        exit 1
      fi
      pi_cleanup_stage() {
        if [ "$pi_link_moved" = true ] && [ -L "$pi_link_backup" ]; then
          if [ ! -e "$pi_destination" ] && [ ! -L "$pi_destination" ]; then
            run ${pkgs.coreutils}/bin/mv -T -- "$pi_link_backup" "$pi_destination"
          else
            run ${pkgs.coreutils}/bin/rm -f -- "$pi_link_backup"
          fi
        fi
        if [ -n "$pi_stage" ] && [ -d "$pi_stage" ]; then
          case "$pi_stage" in
            "$pi_destination_parent"/.pi-profile-migration.*)
              run ${pkgs.coreutils}/bin/rm -rf -- "$pi_stage"
              ;;
          esac
        fi
      }
      trap pi_cleanup_stage EXIT
      trap 'exit 129' HUP
      trap 'exit 130' INT
      trap 'exit 143' TERM

      pi_stage="$(${pkgs.coreutils}/bin/mktemp -d \
        "$pi_destination_parent/.pi-profile-migration.XXXXXX")"
      pi_copy_tree "$pi_destination" "$pi_stage"
      if [ -n "$pi_source_resolved" ] \
        && [ "$pi_source_resolved" != "$pi_destination_resolved" ]; then
        pi_copy_tree "$pi_source" "$pi_stage"
      fi
      run ${pkgs.coreutils}/bin/chmod 0700 -- "$pi_stage"
      run ${pkgs.coreutils}/bin/touch -- "$pi_stage/$pi_stage_ready_name"
      run ${pkgs.coreutils}/bin/mv -T -- "$pi_destination" "$pi_link_backup"
      pi_link_moved=true
      run ${pkgs.coreutils}/bin/mv -T -- "$pi_stage" "$pi_destination"
      pi_stage=
      run ${pkgs.coreutils}/bin/rm -f -- "$pi_link_backup"
      run ${pkgs.coreutils}/bin/rm -f -- "$pi_destination/$pi_stage_ready_name"
      pi_link_moved=false
      trap - EXIT HUP INT TERM
    )

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
          printf '%s\n' \
            "Pi profile migration: source is not a directory: $pi_source" >&2
          exit 1
        fi
        pi_source_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$pi_source")"
      fi

      if [ -L "$pi_destination" ]; then
        if [ ! -d "$pi_destination" ]; then
          printf '%s\n' \
            "Pi profile migration: destination symlink does not resolve to a directory: $pi_destination" >&2
          exit 1
        fi
        pi_replace_legacy_destination_link
      elif [ -n "$pi_source_resolved" ]; then
        if [ -e "$pi_destination" ]; then
          if [ ! -d "$pi_destination" ]; then
            printf '%s\n' \
              "Pi profile migration: destination is not a directory: $pi_destination" >&2
            exit 1
          fi
        else
          run ${pkgs.coreutils}/bin/mkdir -m 0700 -p -- "$pi_destination"
        fi
        pi_destination_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$pi_destination")"
        if [ "$pi_source_resolved" != "$pi_destination_resolved" ]; then
          pi_copy_tree "$pi_source" "$pi_destination"
        fi
      fi
      run ${pkgs.coreutils}/bin/touch -- "$pi_marker"
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
