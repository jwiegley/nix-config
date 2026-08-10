# Home Manager release-skew gate for the shared SSH core — jwiegley/nix-config#29.
#
# Installed at test/home-manager-release-skew.nix and wired as ONE targeted
# `checks.<system>` attribute (see flake.nix), alongside the lock-coherence gate.
# It is deliberately NOT a root-level `nix flake check`: Determinate forces
# every host configuration when `nix flake check` runs, which the repo keeps
# off the hot path (see doc/ARCHITECTURE.md). Build it explicitly:
#
#     nix build .#checks.<system>.home-manager-release-skew
#
# What it proves
# --------------
# config/ssh.nix authors ssh configuration in home-manager MASTER's
# `programs.ssh.settings` (RFC42) shape. Home Manager `release-25.11` — which
# vulcan and the VPS pin — ships only `programs.ssh.matchBlocks` and has NO
# `settings` option. This gate instantiates config/ssh.nix against both master
# and a lib PINNED to that older API (`home-manager-release`, wired in
# flake.nix), then FORCES both to render. Before the dual-API shim, the release
# eval died with:
#
#     error: The option `programs.ssh.settings' does not exist.
#
# i.e. exactly the skew that used to reach a host at lock-bump instead of a
# reviewer at merge. Reverting the shim (emitting `settings` unconditionally)
# reproduces that failure here — the mandated negative test.
#
# The shim is capability-gated on the LIBRARY (`options.programs.ssh ?
# settings`), never on a hostname, so this check drives the SAME core module
# every host evaluates; a hostname gate would reproduce the class of defect the
# programme is removing.
{
  pkgs,
  lib,
  src,
  homeManagerLib,
  homeManagerReleaseLib,
}:

let
  # A stub `my-scripts` makes config/ssh.nix emit its `vulcan_wifi` block, whose
  # `lib.hm.dag.entryBefore [ "vulcan" ]` ordering exercises the translator's
  # DAG + `Match`-header path. `homeManagerConfiguration` re-imports pkgs through
  # `pkgs.overlays`, so the stub must be added with `.extend`, not a bare `//`.
  testPkgs = pkgs.extend (_final: prev: { my-scripts = prev.coreutils; });

  evaluate =
    hmLib:
    hmLib.homeManagerConfiguration {
      pkgs = testPkgs;
      # `vulcan` is a release-25.11 host and the one carrying the wifi override.
      extraSpecialArgs = {
        hostname = "vulcan";
      };
      modules = [
        "${src}/config/ssh.nix"
        {
          # config/ssh.nix reads these two `vars` fields and `hostname`; provide
          # a release-consumer-shaped stub (both release hosts are Linux).
          _module.args.vars = {
            isDarwin = false;
            identityDir = "/home/johnw/.ssh";
          };
          home = {
            username = "johnw";
            homeDirectory = "/home/johnw";
            stateVersion = "23.11";
            # Matched nixpkgs is not the point of this gate; silence the version
            # notice so the log carries signal.
            enableNixpkgsReleaseCheck = false;
          };
        }
      ];
    };

  evaluatedMaster = evaluate homeManagerLib;
  evaluatedRelease = evaluate homeManagerReleaseLib;

  # Gate integrity: the pinned libs must genuinely exercise different APIs.
  masterHasSettings = evaluatedMaster.options.programs.ssh ? settings;
  releaseLacksSettings = !(evaluatedRelease.options.programs.ssh ? settings);

  # Both cores evaluate end to end: the rendered client configs are forced below.
  renderedMasterConfig = evaluatedMaster.config.home.file.".ssh/config".text;
  renderedReleaseConfig = evaluatedRelease.config.home.file.".ssh/config".text;

  # The capability gate chose settings on master and matchBlocks on release.
  tookSettingsBranch = evaluatedMaster.config.programs.ssh.settings != { };
  tookMatchBlocksBranch = evaluatedRelease.config.programs.ssh.matchBlocks != { };

  # Compare only the durable Host * security contract. Other directives and
  # host blocks are intentionally additive and must not churn this fixture.
  expectedSecurityBaseline = {
    ForwardAgent = "no";
    HashKnownHosts = "yes";
    StrictHostKeyChecking = "yes";
    UserKnownHostsFile = "/home/johnw/.config/ssh/known_hosts";
    VerifyHostKeyDNS = "yes";
  };
  normalizeSecurityBaseline =
    attrs:
    lib.mapAttrs (
      _name: value: if lib.isBool value then if value then "yes" else "no" else toString value
    ) (lib.filterAttrs (name: _value: builtins.hasAttr name expectedSecurityBaseline) attrs);
  securityBaselines = {
    master = normalizeSecurityBaseline evaluatedMaster.config.programs.ssh.settings."*".data;
    release =
      normalizeSecurityBaseline
        evaluatedRelease.config.programs.ssh.matchBlocks."*".data.extraOptions;
  };
  expectedSecurityBaselines = {
    master = expectedSecurityBaseline;
    release = expectedSecurityBaseline;
  };
  defaultConfigValues = {
    master = evaluatedMaster.config.programs.ssh.enableDefaultConfig;
    release = evaluatedRelease.config.programs.ssh.enableDefaultConfig;
  };

  # DAG ordering survives the settings->matchBlocks translation: the
  # `vulcan_wifi` `Match` block must precede `Host vulcan`, or ssh's
  # first-match-wins would discard the wifi HostName override.
  charIndex =
    needle: haystack:
    let
      parts = lib.splitString needle haystack;
    in
    if builtins.length parts < 2 then -1 else builtins.stringLength (builtins.head parts);
  wifiIndex = charIndex "Match host vulcan exec" renderedReleaseConfig;
  vulcanIndex = charIndex "\nHost vulcan\n" renderedReleaseConfig;
  wifiBeforeVulcan = wifiIndex >= 0 && vulcanIndex >= 0 && wifiIndex < vulcanIndex;
in
assert lib.assertMsg masterHasSettings ''
  home-manager-release-skew: the master Home Manager lib no longer exposes
  `programs.ssh.settings`; this fixture no longer exercises both APIs.'';
assert lib.assertMsg releaseLacksSettings ''
  home-manager-release-skew: the pinned home-manager-release lib now exposes
  `programs.ssh.settings`. The release input has advanced past the skew this
  gate guards; retire or re-point it (jwiegley/nix-config#29).'';
assert lib.assertMsg tookSettingsBranch ''
  home-manager-release-skew: the shim did not populate `programs.ssh.settings`
  on the master lib — the capability gate in config/ssh.nix misfired.'';
assert lib.assertMsg tookMatchBlocksBranch ''
  home-manager-release-skew: the shim did not populate `programs.ssh.matchBlocks`
  on the release lib — the capability gate in config/ssh.nix misfired.'';
assert lib.assertMsg (securityBaselines == expectedSecurityBaselines) ''
  home-manager-release-skew: the Host * security baseline weakened or diverged
  between Home Manager APIs. Got ${builtins.toJSON securityBaselines}.'';
assert lib.assertMsg
  (
    defaultConfigValues == {
      master = false;
      release = false;
    }
  )
  ''
    home-manager-release-skew: `programs.ssh.enableDefaultConfig` must be false on
    both Home Manager APIs. Got ${builtins.toJSON defaultConfigValues}.'';
assert lib.assertMsg wifiBeforeVulcan ''
  home-manager-release-skew: the `vulcan_wifi` Match block did not sort before
  `Host vulcan`. DAG ordering was lost in the settings->matchBlocks translation
  (check the `entryBetween before after` argument order).'';
pkgs.runCommand "home-manager-release-skew"
  {
    # Embed both fully-rendered configs so the derivation cannot be produced
    # unless the core actually evaluated against both APIs.
    masterRendered = renderedMasterConfig;
    releaseRendered = renderedReleaseConfig;
    passAsFile = [
      "masterRendered"
      "releaseRendered"
    ];
  }
  ''
    test -s "$masterRenderedPath"
    test -s "$releaseRenderedPath"
    grep -q '^Host \*$' "$masterRenderedPath"
    grep -q '^Host \*$' "$releaseRenderedPath"
    grep -q '^Host vulcan$' "$releaseRenderedPath"
    grep -q '^Match host vulcan exec ' "$releaseRenderedPath"
    touch "$out"
  ''
