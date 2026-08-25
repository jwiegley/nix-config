{
  homeManagerLib,
  pkgs,
  src,
}:

let
  lib = pkgs.lib // {
    inherit (homeManagerLib) hm;
  };
  runtimeCheck = "${src}/test/ai/model-sync-runtime-check.py";
  modelSelection = import "${src}/config/ai/models.nix";
  modelSync = import "${src}/config/ai/model-sync.nix" {
    inherit lib pkgs;
    models = modelSelection;
    omlxBaseUrl = "http://model-sync.invalid/v1";
    tools = {
      defaults = "fake-bin/defaults";
      devonthinkKeyPresent = "fake-bin/devonthink";
      mkdir = "fake-bin/mkdir";
      mktemp = "fake-bin/mktemp";
      mv = "fake-bin/mv";
      pgrep = "fake-bin/pgrep";
      rm = "fake-bin/rm";
      security = "fake-bin/security";
    };
  };
  inherit (modelSync) desiredPreferences;
  digestFor =
    preferences:
    builtins.hashString "sha256" (
      builtins.toJSON {
        schema = 1;
        inherit preferences;
      }
    );
  digestContract = candidate: candidate.digest == digestFor candidate.desiredPreferences;
  preferenceIndexes = lib.imap0 (index: _: index) desiredPreferences;
  mutatePreference =
    target:
    lib.imap0 (
      index: preference:
      if index == target then
        preference
        // {
          value = "${preference.value}:digest-mutant-${toString target}";
        }
      else
        preference
    ) desiredPreferences;
  digestMutants = map (
    target: modelSync // { desiredPreferences = mutatePreference target; }
  ) preferenceIndexes;
in
assert desiredPreferences != [ ];
assert modelSync.activation.before == [ ];
assert modelSync.activation.after == [ "linkGeneration" ];
assert modelSync.activation.data == modelSync.script;
assert digestContract modelSync;
# Each desired entry must invalidate the digest. This fails if the digest ever
# returns to a hand-maintained subset of the preference state.
assert builtins.all (candidate: !(digestContract candidate)) digestMutants;
pkgs.runCommand "model-sync-state"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.python3
    ];
  }
  ''
    cp ${src}/test/ai/model-sync-fake-tool.sh fake-tool.sh
    chmod +x fake-tool.sh
    python3 ${lib.escapeShellArg runtimeCheck} \
      ${pkgs.writeShellScript "model-sync-runtime" modelSync.script} \
      ${lib.escapeShellArg modelSync.digest} \
      ${pkgs.writeText "model-sync-preferences.json" (builtins.toJSON desiredPreferences)} \
      "$PWD/fake-tool.sh"
    touch "$out"
  ''
