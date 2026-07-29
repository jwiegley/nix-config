{
  darwinConfigurations,
  pkgs,
}:

let
  inherit (pkgs) lib;
  schema = "darwin-value-surface/2";
  hosts = [
    "hera"
    "clio"
  ];
  surfaces = [
    "environment"
    "homebrew"
    "launchd"
    "nix"
    "services"
    "system"
    "users"
  ];
  unreadable = "<unreadable: removed or throwing option>";
  helpers = import ./surface-helpers.nix;
  project = import ./darwin-surface.nix;
  projection = {
    "test/darwin/darwin-surface.nix" = builtins.hashFile "sha256" ./darwin-surface.nix;
    "test/darwin/surface-helpers.nix" = builtins.hashFile "sha256" ./surface-helpers.nix;
    "bin/darwin-surface-diff" = builtins.hashFile "sha256" ../../bin/darwin-surface-diff;
  };
  actualHosts = lib.genAttrs hosts (host: project darwinConfigurations.${host});

  baselineDir = ../baseline;
  baselineNames = builtins.filter (
    name: lib.hasPrefix "darwin-surface-" name && lib.hasSuffix ".json" name
  ) (builtins.attrNames (builtins.readDir baselineDir));
  baselineName =
    if builtins.length baselineNames == 1 then
      builtins.head baselineNames
    else
      throw "expected exactly one test/baseline/darwin-surface-*.json, found ${builtins.toJSON baselineNames}";
  baseline = builtins.fromJSON (builtins.readFile (baselineDir + "/${baselineName}"));

  checks = [
    {
      ok = (baseline.schema or null) == schema;
      message = "baseline schema must be ${schema}";
    }
    {
      ok = (baseline.projection or { }) == projection;
      message = "baseline projector/normalizer identity is stale; regenerate it";
    }
    {
      ok = builtins.attrNames (baseline.hosts or { }) == builtins.sort builtins.lessThan hosts;
      message = "baseline must contain exactly hera and clio";
    }
    {
      ok =
        helpers.derivationName {
          pname = "same";
          name = "package-1.0";
        } != helpers.derivationName {
          pname = "same";
          name = "package-2.0";
        };
      message = "package projection must preserve derivation names, not collapse to pname";
    }
    {
      ok = !(builtins.tryEval (builtins.deepSeq (helpers.homebrewName "brew" { }) true)).success;
      message = "unnamed Homebrew objects must fail closed instead of sharing a sentinel";
    }
  ]
  ++ lib.concatMap (
    host:
    let
      surface = actualHosts.${host};
    in
    [
      {
        ok = builtins.attrNames surface == surfaces;
        message = "${host} must project exactly the seven Darwin surfaces";
      }
      {
        ok = surface.launchd.userAgentNames != [ ];
        message = "${host} launchd.user.agents projection is empty (wrong launchd path?)";
      }
      {
        ok = surface.launchd.daemonNames != [ ];
        message = "${host} launchd.daemons projection is empty";
      }
      {
        ok = surface.launchd.agentNames == [ ];
        message = "${host} legacy launchd.agents tripwire unexpectedly changed";
      }
      {
        ok = (surface.system.defaults.alf or null) == unreadable;
        message = "${host} must record the unreadable system.defaults.alf domain";
      }
      {
        ok = surface.nix.maxJobs != null && surface.nix.buildMachines != [ ];
        message = "${host} disabled-Nix settings/builders projection is vacuous";
      }
    ]
  ) hosts;
  failures = map (check: check.message) (builtins.filter (check: !check.ok) checks);
  structuralChecks =
    if failures == [ ] then
      true
    else
      throw "Darwin value-surface structural checks failed:\n${lib.concatStringsSep "\n" failures}";

  expectedFile = pkgs.writeText "darwin-value-surface-expected.json" (builtins.toJSON baseline.hosts);
  actualFile = pkgs.writeText "darwin-value-surface-actual.json" (
    builtins.unsafeDiscardStringContext (builtins.toJSON actualHosts)
  );
in
assert structuralChecks;
pkgs.runCommand "check-darwin-value-surface"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    ${pkgs.python3}/bin/python3 ${../../bin/darwin-surface-diff} \
      --normalize-store \
      ${expectedFile} \
      ${actualFile}
    touch "$out"
  ''
