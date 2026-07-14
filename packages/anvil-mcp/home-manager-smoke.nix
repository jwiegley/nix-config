{
  homeManagerLib,
  lib,
  runCommand,
  testPkgs,
}:

let
  inherit (testPkgs.stdenv) isDarwin isLinux;

  evaluate =
    {
      dedicated,
      perAgent,
    }:
    homeManagerLib.homeManagerConfiguration {
      pkgs = testPkgs;
      modules = [
        ../../config/anvil.nix
        {
          home = {
            username = "anvil-test";
            homeDirectory = "/tmp/anvil-home-manager-test";
            stateVersion = "23.11";
          };
          johnw.anvil = {
            useHeadlessEmacs = isLinux && dedicated;
            useDedicatedDarwinEmacs = isDarwin && dedicated;
            usePerAgentDaemon = perAgent;
          };
        }
      ];
    };

  defaultMode = evaluate {
    dedicated = false;
    perAgent = true;
  };
  perAgentMode = evaluate {
    dedicated = true;
    perAgent = true;
  };
  hostMode = evaluate {
    dedicated = true;
    perAgent = false;
  };

  backends =
    evaluation:
    lib.filter builtins.isString (
      map (package: package.backend or null) evaluation.config.home.packages
    );
  expectedDefaultBackend = if isLinux then "nelisp" else "interactive-emacs";

  servicePresent =
    evaluation:
    if isLinux then
      evaluation.config.systemd.user.services ? anvil-headless-emacs
    else
      evaluation.config.launchd.agents ? anvil-headless-emacs;
in
assert lib.assertMsg (isLinux || isDarwin) "Anvil Home Manager smoke requires Linux or Darwin";
assert lib.assertMsg (
  backends defaultMode == [ expectedDefaultBackend ]
) "Anvil default mode selected an unexpected package";
assert lib.assertMsg (
  backends perAgentMode == [ "dedicated-emacs" ]
) "Anvil per-agent mode did not select the dedicated package";
assert lib.assertMsg (
  backends hostMode == [ "dedicated-emacs" ]
) "Anvil host mode did not select the dedicated package";
assert lib.assertMsg (
  !(servicePresent defaultMode)
) "Anvil default mode unexpectedly installed a global service";
assert lib.assertMsg (
  !(servicePresent perAgentMode)
) "Anvil per-agent mode unexpectedly installed a global service";
assert lib.assertMsg (servicePresent hostMode) "Anvil host mode omitted its global service";
assert lib.assertMsg (
  perAgentMode.config.home.sessionVariables.MCP_TIMEOUT == "180000"
) "Anvil dedicated mode drifted from the 180-second startup fallback";
runCommand "anvil-home-manager-smoke" { } ''
  touch "$out"
''
