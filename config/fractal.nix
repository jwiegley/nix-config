{
  hostname,
  lib,
  pkgs,
  ...
}:

let
  jsonFormat = pkgs.formats.json { };
  enabled = hostname == "hera";

  piModels = jsonFormat.generate "pi-models.json" {
    providers.litellm = {
      baseUrl = "https://litellm.vulcan.lan/v1";
      api = "openai-responses";
      apiKey = "!${pkgs.pass}/bin/pass litellm.vulcan.lan | ${pkgs.coreutils}/bin/head -n 1";
      authHeader = true;
      models = [
        {
          id = "positron_openai/gpt-5.6-sol";
          name = "GPT-5.6 Sol (LiteLLM Vulcan)";
          reasoning = true;
          thinkingLevelMap = {
            off = "none";
            minimal = null;
            xhigh = "xhigh";
            max = null;
          };
          input = [
            "text"
            "image"
          ];
          contextWindow = 1050000;
          maxTokens = 128000;
          cost = {
            input = 5;
            output = 30;
            cacheRead = 0.5;
            cacheWrite = 6.25;
            tiers = [
              {
                inputTokensAbove = 272000;
                input = 10;
                output = 45;
                cacheRead = 1;
                cacheWrite = 12.5;
              }
            ];
          };
        }
      ];
    };
  };
in
{
  config = lib.mkIf enabled {
    home.file = {
      ".local/bin/codex".source = ../bin/codex-litellm;
    }
    // lib.optionalAttrs (pkgs ? plasma-fractal && pkgs ? plasma-wiki) {
      ".agents/skills/fractal".source = "${pkgs.plasma-fractal}/share/skills/fractal";
      ".agents/skills/wiki".source = "${pkgs.plasma-wiki}/share/skills/wiki";
    };

    xdg.configFile."pi/agent/models.json".source = piModels;
  };
}
