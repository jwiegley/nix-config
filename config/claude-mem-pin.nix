{
  pkgs,
  tools ? { },
}:

let
  commands = {
    chgrp = "${pkgs.coreutils}/bin/chgrp";
    chmod = "${pkgs.coreutils}/bin/chmod";
    jq = "${pkgs.jq}/bin/jq";
    mktemp = "${pkgs.coreutils}/bin/mktemp";
    mv = "${pkgs.coreutils}/bin/mv";
    rm = "${pkgs.coreutils}/bin/rm";
  }
  // tools;
in
pkgs.writeShellApplication {
  name = "claude-mem-pin";
  text = ''
    if [ "$#" -ne 3 ]; then
      echo "usage: claude-mem-pin SETTINGS CLAUDE DRY_RUN_COMMAND" >&2
      exit 2
    fi

    settings=$1
    claude=$2
    dry_run_command=$3

    if [ ! -e "$settings" ] && [ ! -L "$settings" ]; then
      exit 0
    fi
    if [ -L "$settings" ] || [ ! -f "$settings" ]; then
      echo "claude-mem: refusing non-regular settings: $settings" >&2
      exit 1
    fi
    if [ -n "$dry_run_command" ]; then
      echo "Would pin claude-mem CLAUDE_CODE_PATH -> $claude"
      exit 0
    fi

    current="$(${commands.jq} -r '.CLAUDE_CODE_PATH // ""' -- "$settings")"
    [ "$current" != "$claude" ] || exit 0

    temporary=
    cleanup() {
      local status=$?
      if [ -n "$temporary" ]; then
        ${commands.rm} -f -- "$temporary" || :
      fi
      exit "$status"
    }
    trap cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    temporary="$(${commands.mktemp} "$settings.XXXXXX")"
    ${commands.jq} --arg path "$claude" ".CLAUDE_CODE_PATH = \$path" -- "$settings" >"$temporary"
    ${commands.chgrp} --reference="$settings" "$temporary"
    ${commands.chmod} --reference="$settings" "$temporary"
    ${commands.mv} -f -- "$temporary" "$settings"
    trap - EXIT HUP INT TERM

    echo "claude-mem: pinned CLAUDE_CODE_PATH -> $claude"
  '';
}
