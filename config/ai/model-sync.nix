{ lib, pkgs }:

let
  devonthinkKeyPresent = pkgs.writeShellScript "devonthink-compatible-key-present" ''
    exec /usr/bin/osascript -l JavaScript <<'JXA'
    ObjC.import('Foundation')
    ObjC.import('stdlib')

    try {
      const preferences = $.NSUserDefaults.alloc.initWithSuiteName(
        'com.devon-technologies.think'
      )
      const value = preferences.objectForKey('OpenAI (Compatible)Key')
      const present = value !== null && value !== undefined && Number(value.length) > 0
      $.exit(present ? 0 : 1)
    } catch (_) {
      $.exit(1)
    }
    JXA
  '';

  defaultTools = {
    pgrep = "/usr/bin/pgrep";
    defaults = "/usr/bin/defaults";
    devonthinkKeyPresent = toString devonthinkKeyPresent;
    security = "/usr/bin/security";
    mkdir = "${pkgs.coreutils}/bin/mkdir";
    mktemp = "${pkgs.coreutils}/bin/mktemp";
    mv = "${pkgs.coreutils}/bin/mv";
    rm = "${pkgs.coreutils}/bin/rm";
  };

  expectedToolNames = [
    "defaults"
    "devonthinkKeyPresent"
    "mkdir"
    "mktemp"
    "mv"
    "pgrep"
    "rm"
    "security"
  ];
in
{
  syncInputs,
  tools ? defaultTools,
}:

assert builtins.isAttrs syncInputs;
assert
  builtins.attrNames syncInputs == [
    "chatUrl"
    "model"
    "provider"
  ];
assert builtins.all builtins.isString (builtins.attrValues syncInputs);
assert builtins.all (value: builtins.stringLength value > 0) (builtins.attrValues syncInputs);
assert builtins.isAttrs tools;
assert builtins.attrNames tools == expectedToolNames;
assert builtins.all builtins.isString (builtins.attrValues tools);

let
  digest = builtins.hashString "sha256" (
    builtins.toJSON {
      schema = 1;
      inherit (syncInputs) provider model chatUrl;
    }
  );
  quote = lib.escapeShellArg;
  script = ''
    (
      set -euo pipefail
      umask 077

      expected_digest=${quote digest}
      state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
      state_dir="$state_home/nix-managed-ai"
      stamp="$state_dir/model-sync-v1.sha256"

      previous_digest=
      stamp_has_extra=0
      if [[ -f "$stamp" ]]; then
        exec 3< "$stamp"
        IFS= read -r previous_digest <&3 || true
        extra_stamp_line=
        if IFS= read -r extra_stamp_line <&3 || [[ -n "$extra_stamp_line" ]]; then
          stamp_has_extra=1
        fi
        exec 3<&-
      fi
      if [[ "$stamp_has_extra" -eq 0 && "$previous_digest" == "$expected_digest" ]]; then
        exit 0
      fi

      pgrep_tool=${quote tools.pgrep}
      defaults_tool=${quote tools.defaults}
      devonthink_key_present=${quote tools.devonthinkKeyPresent}
      security_tool=${quote tools.security}
      mkdir_tool=${quote tools.mkdir}
      mktemp_tool=${quote tools.mktemp}
      mv_tool=${quote tools.mv}
      rm_tool=${quote tools.rm}

      model=${quote syncInputs.model}
      chat_url=${quote syncInputs.chatUrl}

      fail() {
        printf '%s\n' "nix-managed model sync: $1" >&2
        exit 1
      }

      app_is_running() {
        local status
        if "$pgrep_tool" -x "$1" >/dev/null 2>&1; then
          return 0
        else
          status=$?
        fi
        if [[ "$status" -eq 1 ]]; then
          return 1
        fi
        fail "application process check failed"
      }

      write_preference() {
        local domain=$1
        local key=$2
        local type=$3
        local value=$4

        "$defaults_tool" write "$domain" "$key" "$type" "$value" \
          >/dev/null 2>&1 \
          || fail "preference update failed"
      }

      verify_preference() {
        local domain=$1
        local key=$2
        local expected=$3
        local actual

        actual="$("$defaults_tool" read "$domain" "$key" 2>/dev/null)" \
          || fail "preference verification failed"
        [[ "$actual" == "$expected" ]] \
          || fail "preference verification failed"
      }

      if app_is_running "DEVONthink" \
        || app_is_running "DEVONthink 3" \
        || app_is_running "iTerm2"
      then
        printf '%s\n' \
          "nix-managed model sync: deferred while DEVONthink or iTerm2 is running" \
          >&2
        exit 0
      fi

      "$devonthink_key_present" >/dev/null 2>&1 \
        || fail "DEVONthink compatible credential is missing"
      "$security_tool" find-generic-password \
        -s "iTerm2 API Keys" \
        -a "OpenAI API Key for iTerm2" \
        >/dev/null 2>&1 \
        || fail "iTerm2 credential metadata is missing"

      devonthink_domain="com.devon-technologies.think"
      write_preference "$devonthink_domain" "ChatEngine" -int 2
      write_preference "$devonthink_domain" "ChatModel-OpenAI (Compatible)" -string "$model"
      write_preference "$devonthink_domain" "OpenAI (Compatible)URL" -string "$chat_url"
      write_preference "$devonthink_domain" "ChatSummaryEngine" -int 2
      write_preference "$devonthink_domain" "ChatSummaryModel" -string "$model"

      verify_preference "$devonthink_domain" "ChatEngine" 2
      verify_preference "$devonthink_domain" "ChatModel-OpenAI (Compatible)" "$model"
      verify_preference "$devonthink_domain" "OpenAI (Compatible)URL" "$chat_url"
      verify_preference "$devonthink_domain" "ChatSummaryEngine" 2
      verify_preference "$devonthink_domain" "ChatSummaryModel" "$model"

      iterm_domain="com.googlecode.iterm2"
      write_preference "$iterm_domain" "UseRecommendedAIModel" -bool false
      write_preference "$iterm_domain" "AiModel" -string "$model"
      write_preference "$iterm_domain" "AITermAPI" -int 1
      write_preference "$iterm_domain" "AitermURL" -string "$chat_url"
      write_preference "$iterm_domain" "AIVendor" -int 2

      verify_preference "$iterm_domain" "UseRecommendedAIModel" 0
      verify_preference "$iterm_domain" "AiModel" "$model"
      verify_preference "$iterm_domain" "AITermAPI" 1
      verify_preference "$iterm_domain" "AitermURL" "$chat_url"
      verify_preference "$iterm_domain" "AIVendor" 2

      "$devonthink_key_present" >/dev/null 2>&1 \
        || fail "DEVONthink compatible credential metadata changed"
      "$security_tool" find-generic-password \
        -s "iTerm2 API Keys" \
        -a "OpenAI API Key for iTerm2" \
        >/dev/null 2>&1 \
        || fail "iTerm2 credential metadata changed"

      "$mkdir_tool" -p -- "$state_dir" >/dev/null 2>&1 \
        || fail "state directory creation failed"
      temporary_stamp=
      cleanup_stamp() {
        if [[ -n "$temporary_stamp" ]]; then
          "$rm_tool" -f -- "$temporary_stamp" >/dev/null 2>&1 \
            || printf '%s\n' "nix-managed model sync: temporary stamp cleanup failed" >&2
        fi
      }
      trap cleanup_stamp EXIT
      trap 'exit 129' HUP
      trap 'exit 130' INT
      trap 'exit 143' TERM
      temporary_stamp="$(
        "$mktemp_tool" "$stamp.tmp.XXXXXX" 2>/dev/null
      )" || fail "temporary stamp creation failed"

      printf '%s\n' "$expected_digest" > "$temporary_stamp" \
        || fail "temporary stamp write failed"
      "$mv_tool" -fT -- "$temporary_stamp" "$stamp" >/dev/null 2>&1 \
        || fail "stamp replacement failed"
      trap - EXIT HUP INT TERM
    )
  '';
in
{
  inherit digest script;
  activation = lib.hm.dag.entryAfter [ "linkGeneration" ] script;
}
