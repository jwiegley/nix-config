{
  homeManagerLib,
  inputs,
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

  packagesForBackend =
    evaluation: backend:
    lib.filter (package: (package.backend or null) == backend) evaluation.config.home.packages;
  hostPackages = packagesForBackend hostMode "dedicated-emacs";
  hostPackage = builtins.head hostPackages;
  hostCommand = "${hostPackage}/bin/anvil-headless-emacs";

  servicePresent =
    evaluation:
    if isLinux then
      evaluation.config.systemd.user.services ? anvil-headless-emacs
    else
      evaluation.config.launchd.agents ? anvil-headless-emacs;
  hostService =
    if isLinux then
      hostMode.config.systemd.user.services.anvil-headless-emacs
    else
      hostMode.config.launchd.agents.anvil-headless-emacs;

  evaluateJohnw =
    {
      hostname,
      moduleInputs ? inputs,
      username ? "anvil-test",
    }:
    homeManagerLib.homeManagerConfiguration {
      pkgs = testPkgs;
      extraSpecialArgs = {
        inherit hostname;
        inputs = moduleInputs;
      };
      modules = [
        ../../config/johnw.nix
        {
          home = {
            inherit username;
            homeDirectory = "/tmp/anvil-home-manager-test";
            stateVersion = "23.11";
          };
          targets.genericLinux.enable = isLinux;
        }
      ];
    };
  evaluateDarwinHome =
    { hostname }:
    homeManagerLib.homeManagerConfiguration {
      pkgs = testPkgs;
      extraSpecialArgs = {
        inherit hostname inputs;
      };
      modules = [
        ../../config/home.nix
        {
          home = {
            username = "anvil-test";
            homeDirectory = "/tmp/anvil-home-manager-test";
            # This topology check uses a minimal package set without John's
            # custom overlays.  Package selection itself is proved above by
            # perAgentMode; force unrelated Darwin packages out of this eval.
            packages = lib.mkForce [ ];
          };
        }
      ];
    };
  darwinHostnames = [
    "hera"
    "clio"
  ];
  darwinEvaluations = lib.genAttrs darwinHostnames (
    hostname: evaluateDarwinHome { inherit hostname; }
  );

  strippedInputs = builtins.removeAttrs inputs [ "promptdeploy" ];
  anvilHosts = import ../../config/anvil-hosts.nix;
  managedHostnames = anvilHosts.clients;
  managedEvaluations = lib.genAttrs managedHostnames (hostname: evaluateJohnw { inherit hostname; });
  positronRemoteLinux = evaluateJohnw {
    hostname = "andoria-08";
    username = "jwiegley";
  };
  expectedPositronNixSettings = {
    cores = 32;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = [ "https://cache.iog.io" ];
    substituters = [
      "https://cache.nixos.org"
      "https://tron.cachix.org"
    ];
  };
  expectedPromptdeployItems =
    hostname:
    [
      "mcp:anvil"
      "skill:anvil"
    ]
    ++
      lib.optionals
        (lib.elem hostname [
          "hera"
          "clio"
        ])
        [
          "mcp:devonthink"
        ];
  strippedUnmanaged = evaluateJohnw {
    hostname = "unmanaged-anvil-test";
    moduleInputs = strippedInputs;
  };
  managedWithPromptdeploy = map (hostname: {
    inherit hostname;
    promptdeploy = managedEvaluations.${hostname}.config.programs.promptdeploy;
  }) managedHostnames;
  strippedManaged = map (hostname: {
    inherit hostname;
    evaluation = evaluateJohnw {
      inherit hostname;
      moduleInputs = strippedInputs;
    };
  }) managedHostnames;
  unmanagedConfigurationEvaluation = builtins.tryEval strippedUnmanaged.config.home.username;

  rawJohnw =
    hostname: moduleInputs:
    import ../../config/johnw.nix {
      inherit hostname lib;
      config = { };
      inputs = moduleInputs;
      pkgs = testPkgs;
    };
  rawStrippedUnmanaged = rawJohnw "unmanaged-anvil-test" strippedInputs;
  rawStrippedManaged = map (hostname: {
    inherit hostname;
    module = rawJohnw hostname strippedInputs;
  }) managedHostnames;
  expectedConvergenceAssertion = hostname: {
    assertion = false;
    message = "Anvil client convergence requires the pinned promptdeploy input on ${hostname}";
  };
  promptdeployRevision = "b08b0ac48a2b26bd3a347f560e031e7baa7076ea";
  promptdeployAnvilConfig = builtins.readFile "${inputs.promptdeploy}/mcp/anvil.yaml";
  promptdeployDevonthinkConfig = builtins.readFile "${inputs.promptdeploy}/mcp/devonthink.yaml";
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
  builtins.length hostPackages == 1
) "Anvil host mode did not select exactly one dedicated package";
assert lib.assertMsg (
  !(servicePresent defaultMode)
) "Anvil default mode unexpectedly installed a global service";
assert lib.assertMsg (
  !(servicePresent perAgentMode)
) "Anvil per-agent mode unexpectedly installed a global service";
assert lib.assertMsg (servicePresent hostMode) "Anvil host mode omitted its global service";
assert lib.assertMsg (
  !isLinux || hostService.Service.ExecStart == [ hostCommand ]
) "Anvil Linux service ExecStart drifted";
assert lib.assertMsg (
  !isLinux || hostService.Service.Restart == "always"
) "Anvil Linux service restart policy drifted";
assert lib.assertMsg (
  !isLinux || hostService.Service.RestartSec == 5
) "Anvil Linux service restart delay drifted";
assert lib.assertMsg (
  !isLinux || hostService.Install.WantedBy == [ "default.target" ]
) "Anvil Linux service target drifted";
assert lib.assertMsg (!isDarwin || hostService.enable) "Anvil Darwin service is disabled";
assert lib.assertMsg (
  !isDarwin || hostService.config.ProgramArguments == [ hostCommand ]
) "Anvil Darwin service command drifted";
assert lib.assertMsg (
  !isDarwin
  ||
    hostService.config.EnvironmentVariables == {
      ANVIL_EMACS_LOCK_CONFLICT_STATUS = "75";
      ANVIL_EMACS_USE_SYSTEM_LOG = "1";
    }
) "Anvil Darwin service environment drifted";
assert lib.assertMsg (
  !isDarwin || hostService.config.RunAtLoad
) "Anvil Darwin service no longer runs at load";
assert lib.assertMsg (
  !isDarwin || hostService.config.KeepAlive
) "Anvil Darwin service is no longer kept alive";
assert lib.assertMsg (
  perAgentMode.config.home.sessionVariables.MCP_TIMEOUT == "330000"
) "Anvil dedicated mode drifted from the 330-second tool fallback";
assert lib.assertMsg unmanagedConfigurationEvaluation.success
  "an unmanaged host without promptdeploy did not evaluate cleanly";
assert lib.assertMsg (
  !isLinux || positronRemoteLinux.config.nix.settings == expectedPositronNixSettings
) "a Positron Linux host drifted from its user-level Nix settings";
assert lib.assertMsg (
  !isLinux
  || (
    !(builtins.hasAttr "trusted-public-keys" positronRemoteLinux.config.nix.settings)
    && !(builtins.hasAttr "extra-trusted-public-keys" positronRemoteLinux.config.nix.settings)
  )
) "a Positron Linux host tried to set daemon-owned trust keys";
assert lib.assertMsg (
  !isLinux || builtins.hasAttr "nix/nix.conf" positronRemoteLinux.config.xdg.configFile
) "a Positron Linux host no longer owns its user-level nix.conf";
assert lib.assertMsg (
  !(rawStrippedUnmanaged.programs ? promptdeploy)
) "an unmanaged host unexpectedly defines promptdeploy";
assert lib.assertMsg (
  rawStrippedUnmanaged.assertions == [ ]
) "an unmanaged host without promptdeploy has a failing assertion";
assert lib.assertMsg (lib.all (
  entry:
  !(entry.module.programs ? promptdeploy)
  && entry.module.assertions == [ (expectedConvergenceAssertion entry.hostname) ]
) rawStrippedManaged) "a managed host lost its fail-closed promptdeploy assertion";
assert lib.assertMsg (lib.all (
  entry: !(builtins.tryEval entry.evaluation.config.home.username).success
) strippedManaged) "a managed host without promptdeploy unexpectedly evaluated successfully";
assert lib.assertMsg (lib.all
  (
    entry:
    entry.promptdeploy.enable
    && entry.promptdeploy.expectedRevision == promptdeployRevision
    && entry.promptdeploy.exactItems == expectedPromptdeployItems entry.hostname
  )
  managedWithPromptdeploy
) "a managed host drifted from the pinned promptdeploy convergence contract";
assert lib.assertMsg (lib.hasInfix ''
  codex:
    startup_timeout_sec: 330
    tool_timeout_sec: 330
'' promptdeployAnvilConfig) "pinned promptdeploy lost the Anvil Codex 330-second deadline contract";
assert lib.assertMsg (lib.hasInfix "name: devonthink" promptdeployDevonthinkConfig)
  "pinned promptdeploy lost the DEVONthink MCP definition";
assert lib.assertMsg (
  !isDarwin
  || lib.all (
    hostname:
    let
      evaluation = darwinEvaluations.${hostname};
    in
    evaluation.config.johnw.anvil.useDedicatedDarwinEmacs
    && evaluation.config.johnw.anvil.usePerAgentDaemon
    && !(servicePresent evaluation)
  ) darwinHostnames
) "a Darwin host wrapper drifted from per-agent dedicated-Emacs topology";
assert lib.assertMsg (
  !isLinux
  || (
    anvilHosts.dedicatedLinux != [ ]
    && lib.all (
      hostname:
      builtins.hasAttr hostname managedEvaluations
      && (
        let
          evaluation = managedEvaluations.${hostname};
        in
        backends evaluation == [ "dedicated-emacs" ]
        && evaluation.config.johnw.anvil.usePerAgentDaemon
        && !(servicePresent evaluation)
      )
    ) anvilHosts.dedicatedLinux
  )
) "a dedicated Linux host drifted from per-agent dedicated-Emacs topology";
assert lib.assertMsg (
  !isLinux
  || (builtins.hasAttr "vps" managedEvaluations && backends managedEvaluations.vps == [ "nelisp" ])
) "vps did not select NeLisp";
runCommand "anvil-home-manager-smoke" { } ''
  touch "$out"
''
