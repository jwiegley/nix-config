{
  config,
  lib,
  pkgs,
  hostname,
  inputs,
  ...
}:
let
  enabled =
    pkgs.stdenv.isDarwin
    && lib.elem hostname [
      "hera"
      "clio"
    ]
    && inputs ? promptdeploy;
  syncLog = "${config.home.homeDirectory}/Library/Logs/sync-llm-clients.log";

  syncLlmClients = pkgs.writeShellApplication {
    name = "sync-llm-clients";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.yq-go
    ];
    # Dollar-prefixed names inside the single-quoted jq programs are jq
    # variables, not shell expansions.
    excludeShellChecks = [ "SC2016" ];
    text = ''
            lock="''${TMPDIR:-/tmp}/sync-llm-clients.lock"
            if ! /usr/bin/shlock -p $$ -f "$lock"; then
              exit 0
            fi
            trap 'rm -f "$lock"' EXIT
            pending=0

            manifest=${lib.escapeShellArg "${inputs.promptdeploy}/models.yaml"}
            provider="$(${pkgs.yq-go}/bin/yq -r '.defaults.provider // ""' "$manifest")"
            model="$(${pkgs.yq-go}/bin/yq -r '.defaults.model // ""' "$manifest")"

            if [[ -z "$provider" || -z "$model" ]]; then
              echo "sync-llm-clients: models.yaml has no defaults.provider/defaults.model" >&2
              exit 1
            fi

            export PROMPTDEPLOY_DEFAULT_PROVIDER="$provider"
            base_url="$(${pkgs.yq-go}/bin/yq -r \
              '.providers[strenv(PROMPTDEPLOY_DEFAULT_PROVIDER)].base_url // ""' \
              "$manifest")"
            base_url="''${base_url%/}"
            if [[ -z "$base_url" ]]; then
              echo "sync-llm-clients: default provider '$provider' has no base_url" >&2
              exit 1
            fi
            chat_url="$base_url/chat/completions"

            if [[ -z "''${LITELLM_API_KEY:-}" ]]; then
              opencode_config="$HOME/.config/opencode/opencode.json"
              if [[ -f "$opencode_config" ]]; then
                LITELLM_API_KEY="$(${pkgs.jq}/bin/jq -r \
                  --arg provider "$provider" \
                  '.provider[$provider].options.apiKey // empty' \
                  "$opencode_config" 2>/dev/null || true)"
                export LITELLM_API_KEY
              fi
            fi
            if [[ -z "''${LITELLM_API_KEY:-}" ]]; then
              keychain_account="$(${pkgs.coreutils}/bin/id -un)"
              LITELLM_API_KEY="$(/usr/bin/security find-generic-password \
                -s 'LiteLLM API Key' -a "$keychain_account" -w 2>/dev/null || true)"
              export LITELLM_API_KEY
            fi
            if [[ -z "''${LITELLM_API_KEY:-}" ]]; then
              echo "sync-llm-clients: LiteLLM credential unavailable; retaining existing client credentials" >&2
              pending=1
            fi

            atomic_jq() {
              local file="$1"
              shift
              local tmp
              tmp="$(mktemp "$file.XXXXXX")"
              if jq "$@" "$file" >"$tmp"; then
                chmod 0600 "$tmp"
                mv "$tmp" "$file"
              else
                rm -f "$tmp"
                return 1
              fi
            }

            handy="$HOME/Library/Application Support/com.pais.handy/settings_store.json"
            if [[ -f "$handy" ]] && ! /usr/bin/pgrep -x handy >/dev/null; then
              if ! atomic_jq "$handy" --arg model "$model" --arg base "$base_url" '
                .settings.post_process_enabled = true
                | .settings.post_process_provider_id = "custom"
                | .settings.post_process_models.custom = $model
                | .settings.post_process_providers = (
                    (.settings.post_process_providers // []) as $providers
                    | if any($providers[]; .id == "custom") then
                      $providers
                      | map(if .id == "custom" then .base_url = $base else . end)
                    else
                      $providers + [{
                        "allow_base_url_edit": true,
                        "base_url": $base,
                        "id": "custom",
                        "label": "Custom",
                        "models_endpoint": "/models",
                        "supports_structured_output": false
                      }]
                    end
                  )
                | if (env.LITELLM_API_KEY // "") != "" then
                    .settings.post_process_api_keys.custom = env.LITELLM_API_KEY
                  else . end
              '; then
                echo "sync-llm-clients: Handy preference update failed; will retry" >&2
                pending=1
              fi
            elif /usr/bin/pgrep -x handy >/dev/null; then
              echo "sync-llm-clients: Handy is running; deferring its preference update" >&2
              pending=1
            else
              echo "sync-llm-clients: Handy preferences do not exist yet" >&2
              pending=1
            fi

            if /usr/bin/pgrep -x DEVONthink >/dev/null \
              || /usr/bin/pgrep -x 'DEVONthink 3' >/dev/null; then
              echo "sync-llm-clients: DEVONthink is running; deferring its preference update" >&2
              pending=1
            else
              /usr/bin/defaults write com.devon-technologies.think ChatEngine -int 2
              /usr/bin/defaults write com.devon-technologies.think \
                'ChatModel-OpenAI (Compatible)' -string "$model"
              /usr/bin/defaults write com.devon-technologies.think \
                'OpenAI (Compatible)URL' -string "$chat_url"
              /usr/bin/defaults write com.devon-technologies.think ChatSummaryEngine -int 2
              /usr/bin/defaults write com.devon-technologies.think ChatSummaryModel -string "$model"

              if [[ -n "''${LITELLM_API_KEY:-}" ]]; then
                /usr/bin/osascript -l JavaScript >/dev/null <<'JXA'
      ObjC.import('Foundation');
      const env = $.NSProcessInfo.processInfo.environment;
      const defaults = $.NSUserDefaults.alloc.initWithSuiteName('com.devon-technologies.think');
      defaults.setObjectForKey(env.objectForKey('LITELLM_API_KEY'), 'OpenAI (Compatible)Key');
      defaults.synchronize;
      null;
      JXA
              fi
            fi

            if /usr/bin/pgrep -x iTerm2 >/dev/null; then
              echo "sync-llm-clients: iTerm2 is running; deferring its preference update" >&2
              pending=1
            else
              /usr/bin/defaults write com.googlecode.iterm2 UseRecommendedAIModel -bool false
              /usr/bin/defaults write com.googlecode.iterm2 AiModel -string "$model"
              /usr/bin/defaults write com.googlecode.iterm2 AITermAPI -int 1
              /usr/bin/defaults write com.googlecode.iterm2 AitermURL -string "$chat_url"
              /usr/bin/defaults write com.googlecode.iterm2 AIVendor -int 2

              # iTerm2 owns this ACL-restricted Keychain item.  A background
              # job can verify its presence, but not read or rotate its value.
              if ! /usr/bin/security find-generic-password \
                -s 'iTerm2 API Keys' \
                -a 'OpenAI API Key for iTerm2' >/dev/null 2>&1; then
                echo "sync-llm-clients: iTerm2 has no OpenAI-compatible API key" >&2
                pending=1
              fi
            fi

            whisper_prefs="$HOME/Library/Containers/com.goodsnooze.MacWhisper/Data/Library/Preferences/com.goodsnooze.MacWhisper.plist"
            if [[ -f "$whisper_prefs" ]]; then
              if /usr/bin/pgrep -x 'Whisper Transcription' >/dev/null; then
                echo "sync-llm-clients: Whisper Transcription is running; deferring its preference update" >&2
                pending=1
              else
                if ! services="$(/usr/bin/plutil -extract configuredAIServices_15july2025 \
                  json -o - "$whisper_prefs" 2>/dev/null)"; then
                  services='[]'
                fi
                service_id="$(printf '%s' "$services" | jq -r '
                  map(try fromjson catch empty)
                  | ([.[] | .custom? | select(.name == "LiteLLM") | .uniqueId][0] // "")
                ')"
                if [[ -z "$service_id" ]]; then
                  service_id="$(/usr/bin/uuidgen)"
                fi
                services="$(printf '%s' "$services" | jq -c \
                  --arg id "$service_id" \
                  --arg base "$base_url" \
                  --arg model "$model" '
                    map(select(
                      (try (fromjson | .custom.uniqueId? // "") catch "") != $id
                    ))
                    | . + [({"custom": {
                        "uniqueId": $id,
                        "name": "LiteLLM",
                        "baseURL": $base,
                        "model": $model,
                        "isMDMManaged": false
                      }} | tojson)]
                  ')"
                whisper_domain="''${whisper_prefs%.plist}"
                whisper_tmp="$(mktemp "$whisper_prefs.XXXXXX")"
                cp "$whisper_prefs" "$whisper_tmp"
                plist_set_string() {
                  local key="$1"
                  if /usr/bin/plutil -extract "$key" raw -o - "$whisper_tmp" \
                    >/dev/null 2>&1; then
                    /usr/bin/plutil -replace "$key" -string "$service_id" "$whisper_tmp"
                  else
                    /usr/bin/plutil -insert "$key" -string "$service_id" "$whisper_tmp"
                  fi
                }
                plist_set_json() {
                  local key="$1"
                  local value="$2"
                  if /usr/bin/plutil -extract "$key" raw -o - "$whisper_tmp" \
                    >/dev/null 2>&1; then
                    /usr/bin/plutil -replace "$key" -json "$value" "$whisper_tmp"
                  else
                    /usr/bin/plutil -insert "$key" -json "$value" "$whisper_tmp"
                  fi
                }
                if plist_set_json configuredAIServices_15july2025 "$services" \
                  && plist_set_string selectedAIServiceID \
                  && plist_set_string selectedAIServiceIDForDictation \
                  && plist_set_string selectedAISummarizationProviderID \
                  && /usr/bin/defaults import "$whisper_domain" "$whisper_tmp" \
                    >/dev/null; then
                  :
                else
                  echo "sync-llm-clients: Whisper Transcription preference update failed; will retry" >&2
                  pending=1
                fi
                rm -f "$whisper_tmp"
                # Whisper Transcription likewise owns the custom service's
                # ACL-restricted credential; only presence is observable here.
                if ! /usr/bin/security find-generic-password \
                  -s 'com.goodsnooze.MacWhisper' \
                  -a "aiservice-custom-$service_id" >/dev/null 2>&1; then
                  echo "sync-llm-clients: save the LiteLLM API key once in Whisper Transcription settings" >&2
                  pending=1
                fi
              fi
            else
              echo "sync-llm-clients: Whisper Transcription preferences do not exist yet" >&2
              pending=1
            fi

            if (( pending )); then
              echo "sync-llm-clients: $model persisted where safe; one or more clients remain pending" >&2
              exit 1
            fi
            echo "sync-llm-clients: configured model routing for $model via $provider ($base_url)"
    '';
  };
in
lib.mkIf enabled {
  home.packages = [ syncLlmClients ];

  launchd.agents.sync-llm-clients = {
    enable = true;
    domain = "gui";
    config = {
      Label = "org.nixos.sync-llm-clients";
      ProgramArguments = [ "${syncLlmClients}/bin/sync-llm-clients" ];
      RunAtLoad = true;
      StartInterval = 900;
      ProcessType = "Background";
      StandardOutPath = syncLog;
      StandardErrorPath = syncLog;
    };
  };

  home.activation.syncLlmClients = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! $DRY_RUN_CMD ${syncLlmClients}/bin/sync-llm-clients; then
      $VERBOSE_ECHO "sync-llm-clients: initial sync failed; launchd will retry"
    fi
  '';
}
