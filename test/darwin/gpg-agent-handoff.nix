{
  darwinConfigurations,
  pkgs,
}:

let
  inherit (pkgs) lib;
  hostnames = [
    "hera"
    "clio"
  ];
  hostData = lib.genAttrs hostnames (
    hostname:
    let
      configuration = darwinConfigurations.${hostname}.config;
      primaryUser = configuration.system.primaryUser;
    in
    {
      inherit primaryUser;
      primaryUid = toString configuration.users.users.${primaryUser}.uid;
      preActivation = pkgs.writeText "${hostname}-gpg-agent-pre-activation" (
        builtins.unsafeDiscardStringContext configuration.system.activationScripts.preActivation.text
      );
      activation = pkgs.writeText "${hostname}-gpg-agent-activation" (
        builtins.unsafeDiscardStringContext configuration.system.activationScripts.script.text
      );
    }
  );
  checkHost =
    hostname:
    let
      data = hostData.${hostname};
    in
    ''
      check_host ${
        lib.escapeShellArgs [
          hostname
          data.primaryUser
          data.primaryUid
          (toString data.preActivation)
          (toString data.activation)
        ]
      }
    '';
in
pkgs.runCommand "check-gpg-agent-handoff"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail

    fail() {
      printf 'gpg-agent handoff check failed: %s\n' "$1" >&2
      exit 1
    }

    assert_contains() {
      local file="$1"
      local needle="$2"
      local context="$3"
      grep -Fq -- "$needle" "$file" || fail "$context: missing $needle"
    }

    assert_excludes() {
      local file="$1"
      local needle="$2"
      local context="$3"
      if grep -Fq -- "$needle" "$file"; then
        fail "$context: unexpectedly contains $needle"
      fi
    }

    line_of() {
      grep -Fnm1 -- "$2" "$1" | cut -d: -f1
    }

    assert_before() {
      local file="$1"
      local earlier="$2"
      local later="$3"
      local context="$4"
      local earlier_line
      local later_line
      earlier_line="$(line_of "$file" "$earlier")"
      later_line="$(line_of "$file" "$later")"
      if (( earlier_line >= later_line )); then
        fail "$context: $earlier must precede $later"
      fi
    }

    check_host() {
      local hostname="$1"
      local primary_user="$2"
      local primary_uid="$3"
      local pre_activation="$4"
      local activation="$5"
      local context="$hostname preActivation"
      local guard='stale_hm_gpg_agent_label=org.nix-community.home.gpg-agent'

      assert_contains "$pre_activation" "$guard" "$context"
      assert_contains "$pre_activation" "\"gui/$primary_uid\"" "$context"
      assert_contains "$pre_activation" "\"user/$primary_uid\"" "$context"
      assert_contains "$pre_activation" "for $primary_user (uid $primary_uid)" "$context"
      assert_contains "$pre_activation" '/bin/launchctl bootout "$stale_hm_gpg_agent_target" >/dev/null 2>&1 || true' "$context"
      assert_contains "$pre_activation" 'if /bin/launchctl print "$stale_hm_gpg_agent_target" >/dev/null 2>&1; then' "$context"
      assert_excludes "$pre_activation" 'org.nixos.gnupg-agent' "$context"

      assert_before "$activation" "$guard" 'setting up launchd services...' "$hostname activation"
      assert_before "$activation" "$guard" 'setting up user launchd services...' "$hostname activation"
      assert_before "$activation" "$guard" "Activating home-manager configuration for $primary_user" "$hostname activation"
    }

    ${lib.concatMapStringsSep "\n" checkHost hostnames}
    touch "$out"
  ''
