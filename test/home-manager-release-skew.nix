# Home Manager release-skew gate for the shared SSH core — jwiegley/nix-config#29.
#
# Installed at test/home-manager-release-skew.nix and wired as ONE targeted
# `checks.<system>` attribute (see flake.nix), alongside the lock-purity gate.
# It is deliberately NOT a root-level `nix flake check`: Determinate forces
# every host configuration when `nix flake check` runs, which the repo keeps
# off the hot path (FLEET-DESIGN-PLAN §8.1). Build it explicitly:
#
#     nix build .#checks.<system>.home-manager-release-skew
#
# What it proves
# --------------
# config/ssh.nix authors ssh configuration in home-manager MASTER's
# `programs.ssh.settings` (RFC42) shape. Home Manager `release-25.11` — which
# vulcan and the VPS pin — ships only `programs.ssh.matchBlocks` and has NO
# `settings` option. This gate instantiates config/ssh.nix against a lib PINNED
# to that older API (`home-manager-release`, wired in flake.nix) and FORCES it
# to render. Before the dual-API shim, that eval died with:
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
  homeManagerReleaseLib,
}:

let
  # A stub `my-scripts` makes config/ssh.nix emit its `vulcan_wifi` block, whose
  # `lib.hm.dag.entryBefore [ "vulcan" ]` ordering exercises the translator's
  # DAG + `Match`-header path. `homeManagerConfiguration` re-imports pkgs through
  # `pkgs.overlays`, so the stub must be added with `.extend`, not a bare `//`.
  testPkgs = pkgs.extend (_final: prev: { my-scripts = prev.coreutils; });

  evaluated = homeManagerReleaseLib.homeManagerConfiguration {
    pkgs = testPkgs;
    # `vulcan` is a release-25.11 host and the one carrying the wifi override.
    extraSpecialArgs = {
      hostname = "vulcan";
    };
    modules = [
      "${src}/config/ssh.nix"
      {
        # config/ssh.nix reads these two `vars` fields and `hostname`; provide a
        # release-consumer-shaped stub (both release hosts are Linux).
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

  # Gate integrity: the pinned lib must genuinely LACK `settings`. If a future
  # bump adds it, the shim would take the master branch and this check would
  # quietly stop testing skew — so fail loudly and demand the input be retired.
  releaseLacksSettings = !(evaluated.options.programs.ssh ? settings);

  # The core evaluates end to end: the rendered client config, forced below.
  renderedConfig = evaluated.config.home.file.".ssh/config".text;

  # The capability gate chose the release branch (matchBlocks), not settings.
  tookMatchBlocksBranch = evaluated.config.programs.ssh.matchBlocks != { };

  # DAG ordering survives the settings->matchBlocks translation: the
  # `vulcan_wifi` `Match` block must precede `Host vulcan`, or ssh's
  # first-match-wins would discard the wifi HostName override.
  charIndex =
    needle: haystack:
    let
      parts = lib.splitString needle haystack;
    in
    if builtins.length parts < 2 then -1 else builtins.stringLength (builtins.head parts);
  wifiIndex = charIndex "Match host vulcan exec" renderedConfig;
  vulcanIndex = charIndex "\nHost vulcan\n" renderedConfig;
  wifiBeforeVulcan = wifiIndex >= 0 && vulcanIndex >= 0 && wifiIndex < vulcanIndex;
in
assert lib.assertMsg releaseLacksSettings ''
  home-manager-release-skew: the pinned home-manager-release lib now exposes
  `programs.ssh.settings`. The release input has advanced past the skew this
  gate guards; retire or re-point it (jwiegley/nix-config#29).'';
assert lib.assertMsg tookMatchBlocksBranch ''
  home-manager-release-skew: the shim did not populate `programs.ssh.matchBlocks`
  on the release lib — the capability gate in config/ssh.nix misfired.'';
assert lib.assertMsg wifiBeforeVulcan ''
  home-manager-release-skew: the `vulcan_wifi` Match block did not sort before
  `Host vulcan`. DAG ordering was lost in the settings->matchBlocks translation
  (check the `entryBetween before after` argument order).'';
pkgs.runCommand "home-manager-release-skew"
  {
    # Embed the fully-rendered config so the derivation cannot be produced
    # unless the core actually evaluated against the release lib.
    rendered = renderedConfig;
    passAsFile = [ "rendered" ];
  }
  ''
    test -s "$renderedPath"
    grep -q '^Host vulcan$' "$renderedPath"
    grep -q '^Match host vulcan exec ' "$renderedPath"
    touch "$out"
  ''
