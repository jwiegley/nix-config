# Single source of truth for managed model selection.
# Move replaced oMLX names to retiredModels so mutable Pi settings migrate away
# from them without repeating model history in consumers or tests.
let
  omlxProviders = [
    "omlx-clio"
    "omlx-hera"
  ];
  omlxRoles = {
    primary = {
      name = "Qwen3.8-27B-oQ4e-mtp";
      providers = omlxProviders;
      retiredNames = [
        "Qwen3.6-27B-oQ6e-mtp"
        "Qwen3.8-27B-oQ6e-mtp-mlx"
      ];
      contextWindow = 262144;
      maxTokens = 81920;
    };
    reasoning = {
      name = "DeepSeek-V4-Flash-0731-MXFP4-MLX";
      providers = [ "omlx-hera" ];
      retiredNames = [ "DeepSeek-V4-Flash-0731-oQ8e-mtp" ];
      contextWindow = 262144;
      maxTokens = 81920;
    };
  };
  omlxRoleValues = builtins.attrValues omlxRoles;
  retiredOmlxModels = builtins.concatLists (map (role: role.retiredNames) omlxRoleValues);
  omlxReplacementPairs = builtins.concatLists (
    map (
      role:
      builtins.concatLists (
        map (
          provider:
          map (retired: {
            name = "${provider}/${retired}";
            value = "${provider}/${role.name}";
          }) role.retiredNames
        ) role.providers
      )
    ) omlxRoleValues
  );
  staleOmlxPatterns = builtins.concatLists (
    map (
      provider:
      map (name: "${provider}/${name}") retiredOmlxModels
      ++ builtins.concatLists (
        map (role: if builtins.elem provider role.providers then [ ] else [ "${provider}/${role.name}" ]) (
          builtins.attrValues omlxRoles
        )
      )
    ) omlxProviders
  );
in
{
  codex = {
    name = "gpt-5.6-sol";
    contextWindow = 1050000;
  };
  openrouter = {
    name = "z-ai/glm-5.2";
    contextWindow = 1048576;
  };
  llamaSwap = {
    name = "GLM-5.2";
    contextWindow = 262144;
  };
  omlx = omlxRoles // {
    providers = omlxProviders;
    retiredModels = retiredOmlxModels;
    replacements = builtins.listToAttrs omlxReplacementPairs;
    stalePatterns = staleOmlxPatterns;
  };
}
