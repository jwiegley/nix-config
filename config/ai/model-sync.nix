{
  lib,
  pkgs,
  # Base URL of the omlx endpoint, supplied from the catalog's profile
  # declaration so this file cannot drift from the one endpoint authority.
  omlxBaseUrl,
  tools ? { },
}:

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

  resolvedTools = {
    pgrep = "/usr/bin/pgrep";
    defaults = "/usr/bin/defaults";
    devonthinkKeyPresent = toString devonthinkKeyPresent;
    security = "/usr/bin/security";
    mkdir = "${pkgs.coreutils}/bin/mkdir";
    mktemp = "${pkgs.coreutils}/bin/mktemp";
    mv = "${pkgs.coreutils}/bin/mv";
    rm = "${pkgs.coreutils}/bin/rm";
  }
  // tools;

  model = "DeepSeek-V4-Flash-0731-MXFP4-MLX";
  chatUrl = "${omlxBaseUrl}/chat/completions";

  # One authority feeds stamp invalidation, preference writes, and read-back
  # verification. Keep entries grouped to preserve the activation order: all
  # writes for an application are verified before the next application.
  desiredState = [
    {
      domain = "com.devon-technologies.think";
      preferences = [
        {
          key = "ChatEngine";
          type = "-int";
          value = "2";
          expected = "2";
        }
        {
          key = "ChatModel-OpenAI (Compatible)";
          type = "-string";
          value = model;
          expected = model;
        }
        {
          key = "OpenAI (Compatible)URL";
          type = "-string";
          value = chatUrl;
          expected = chatUrl;
        }
        {
          key = "ChatSummaryEngine";
          type = "-int";
          value = "2";
          expected = "2";
        }
        {
          key = "ChatSummaryModel";
          type = "-string";
          value = model;
          expected = model;
        }
      ];
    }
    {
      domain = "com.googlecode.iterm2";
      preferences = [
        {
          key = "UseRecommendedAIModel";
          type = "-bool";
          value = "false";
          expected = "0";
        }
        {
          key = "AiModel";
          type = "-string";
          value = model;
          expected = model;
        }
        {
          key = "AITermAPI";
          type = "-int";
          value = "1";
          expected = "1";
        }
        {
          key = "AitermURL";
          type = "-string";
          value = chatUrl;
          expected = chatUrl;
        }
        {
          key = "AIVendor";
          type = "-int";
          value = "2";
          expected = "2";
        }
      ];
    }
  ];
  desiredPreferences = lib.concatMap (
    state: map (preference: preference // { inherit (state) domain; }) state.preferences
  ) desiredState;
  digest = builtins.hashString "sha256" (
    builtins.toJSON {
      schema = 1;
      preferences = desiredPreferences;
    }
  );
  quote = lib.escapeShellArg;
  renderWrite =
    preference:
    "write_preference ${quote preference.domain} ${quote preference.key} ${quote preference.type} ${quote preference.value}";
  renderVerification =
    preference:
    "verify_preference ${quote preference.domain} ${quote preference.key} ${quote preference.expected}";
  renderState =
    state:
    let
      preferences = map (preference: preference // { inherit (state) domain; }) state.preferences;
    in
    ''
      ${lib.concatMapStringsSep "\n" renderWrite preferences}

      ${lib.concatMapStringsSep "\n" renderVerification preferences}
    '';
  script = ''
    (
      set -euo pipefail
      umask 077

      expected_digest=${quote digest}
      state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
      state_dir="$state_home/nix-managed-ai"
      stamp="$state_dir/model-sync-v1.sha256"

      if [[ -v DRY_RUN ]]; then
        printf '%s\n' \
          "Would reconcile DEVONthink and iTerm2 model defaults and $stamp"
        exit 0
      fi

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

      pgrep_tool=${quote resolvedTools.pgrep}
      defaults_tool=${quote resolvedTools.defaults}
      devonthink_key_present=${quote resolvedTools.devonthinkKeyPresent}
      security_tool=${quote resolvedTools.security}
      mkdir_tool=${quote resolvedTools.mkdir}
      mktemp_tool=${quote resolvedTools.mktemp}
      mv_tool=${quote resolvedTools.mv}
      rm_tool=${quote resolvedTools.rm}

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

      ${lib.concatMapStringsSep "\n" renderState desiredState}

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
  inherit desiredPreferences digest script;
  activation = lib.hm.dag.entryAfter [ "linkGeneration" ] script;
}
