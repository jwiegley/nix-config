{
  darwinConfigurations,
  homeConfigurations,
  nixosHomeEvaluationFixtures,
  pkgs,
}:

let
  config =
    if pkgs.stdenv.hostPlatform.isDarwin then
      darwinConfigurations.hera.config.home-manager.users.johnw
    else if pkgs.stdenv.hostPlatform.system == "aarch64-linux" then
      nixosHomeEvaluationFixtures.vulcan.config
    else
      homeConfigurations."jwiegley@x86_64-linux".config;
  activation = config.home.activation.aiManagedPiBlackholePolicy;
in
assert activation.before == [ ];
assert activation.after == [ "linkGeneration" ];
pkgs.runCommand "pi-blackhole-policy" { } ''
  export HOME="$TMPDIR/home"
  config_dir="$HOME/.config/pi/agent/pi-blackhole"
  config_path="$config_dir/pi-blackhole-config.json"

  export DRY_RUN=1
  ${activation.data}
  [ ! -e "$config_dir" ]
  unset DRY_RUN

  ${activation.data}
  ${pkgs.jq}/bin/jq -e '
    .memory == true
    and .compaction == "auto"
    and .compactionEngine == "blackhole"
    and .midRunCompaction == "resume"
  ' "$config_path" >/dev/null
  [ "$(${pkgs.coreutils}/bin/stat -c %a "$config_dir")" = 700 ]
  [ "$(${pkgs.coreutils}/bin/stat -c %a "$config_path")" = 600 ]

  ${pkgs.jq}/bin/jq '. + {
    fixture: "preserved",
    noAutoCompact: true,
    passive: true,
    overrideDefaultCompaction: false
  }' "$config_path" > "$config_path.stale"
  ${pkgs.coreutils}/bin/mv "$config_path.stale" "$config_path"
  ${activation.data}
  ${pkgs.jq}/bin/jq -e '
    .fixture == "preserved"
    and .memory == true
    and .compaction == "auto"
    and .compactionEngine == "blackhole"
    and .midRunCompaction == "resume"
    and (has("noAutoCompact") | not)
    and (has("passive") | not)
    and (has("overrideDefaultCompaction") | not)
  ' "$config_path" >/dev/null

  ${pkgs.coreutils}/bin/chmod 0644 "$config_path"
  inode_before="$(${pkgs.coreutils}/bin/stat -c %i "$config_path")"
  ${activation.data}
  inode_after="$(${pkgs.coreutils}/bin/stat -c %i "$config_path")"
  [ "$inode_before" = "$inode_after" ]
  [ "$(${pkgs.coreutils}/bin/stat -c %a "$config_path")" = 600 ]

  printf '%s\n' '{invalid' > "$config_path.invalid"
  ${pkgs.coreutils}/bin/mv "$config_path.invalid" "$config_path"
  if ${activation.data}
  then
    echo "Blackhole policy accepted invalid JSON" >&2
    exit 1
  fi
  [ "$(cat "$config_path")" = '{invalid' ]

  export HOME="$TMPDIR/symlink-home"
  config_dir="$HOME/.config/pi/agent/pi-blackhole"
  ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/pi/agent"
  ${pkgs.coreutils}/bin/mkdir -p "$HOME/redirected-blackhole"
  ${pkgs.coreutils}/bin/ln -s "$HOME/redirected-blackhole" "$config_dir"
  if ${activation.data}
  then
    echo "Blackhole policy followed a redirected configuration directory" >&2
    exit 1
  fi
  [ -z "$(${pkgs.findutils}/bin/find "$HOME/redirected-blackhole" -mindepth 1 -print -quit)" ]

  export HOME="$TMPDIR/config-symlink-home"
  config_dir="$HOME/.config/pi/agent/pi-blackhole"
  config_path="$config_dir/pi-blackhole-config.json"
  sentinel="$HOME/blackhole-sentinel.json"
  ${pkgs.coreutils}/bin/mkdir -p "$config_dir"
  printf '%s\n' '{"sentinel":true}' > "$sentinel"
  ${pkgs.coreutils}/bin/ln -s "$sentinel" "$config_path"
  if ${activation.data}
  then
    echo "Blackhole policy followed a redirected configuration file" >&2
    exit 1
  fi
  [ -L "$config_path" ]
  [ "$(cat "$sentinel")" = '{"sentinel":true}' ]

  touch "$out"
''
