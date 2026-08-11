{
  homeManagerLib,
  pkgs,
  src,
}:

let
  lib = pkgs.lib // {
    inherit (homeManagerLib) hm;
  };
  modelSync = import "${src}/config/ai/model-sync.nix" {
    inherit lib pkgs;
    omlxBaseUrl = "http://model-sync.invalid/v1";
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
  occurrences = needle: haystack: (builtins.length (lib.splitString needle haystack)) - 1;
  writeCall =
    preference:
    "write_preference ${lib.escapeShellArg preference.domain} ${lib.escapeShellArg preference.key} ${lib.escapeShellArg preference.type} ${lib.escapeShellArg preference.value}";
  verificationCall =
    preference:
    "verify_preference ${lib.escapeShellArg preference.domain} ${lib.escapeShellArg preference.key} ${lib.escapeShellArg preference.expected}";
  invocationContract =
    call: prefix: candidate:
    builtins.all (
      preference: occurrences (call preference) candidate.script == 1
    ) candidate.desiredPreferences
    && occurrences prefix candidate.script == builtins.length candidate.desiredPreferences;
  digestContract = candidate: candidate.digest == digestFor candidate.desiredPreferences;
  writeContract = invocationContract writeCall "write_preference ";
  verificationContract = invocationContract verificationCall "verify_preference ";
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
  invocationMutants =
    call:
    lib.concatMap (preference: [
      (
        modelSync
        // {
          script = lib.replaceStrings [ (call preference) ] [ "" ] modelSync.script;
        }
      )
      (
        modelSync
        // {
          script = "${modelSync.script}\n${call preference}\n";
        }
      )
    ]) desiredPreferences;
in
assert desiredPreferences != [ ];
assert modelSync.activation.before == [ ];
assert modelSync.activation.after == [ "linkGeneration" ];
assert modelSync.activation.data == modelSync.script;
assert digestContract modelSync;
assert writeContract modelSync;
assert verificationContract modelSync;
# Each desired entry must invalidate the digest. This fails if the digest ever
# returns to a hand-maintained subset of the preference state.
assert builtins.all (candidate: !(digestContract candidate)) digestMutants;
# Deleting or duplicating any generated call must be observable, for both
# writes and read-back verification.
assert builtins.all (candidate: !(writeContract candidate)) (invocationMutants writeCall);
assert builtins.all (candidate: !(verificationContract candidate)) (
  invocationMutants verificationCall
);
pkgs.runCommand "model-sync-state" { } "touch $out"
