{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.johnw.agentDeck;
  agentDeck = pkgs.agent-deck;
  bridgePython = pkgs.python3.withPackages (
    pythonPackages: with pythonPackages; [
      discordpy
      toml
    ]
  );

  homeDirectory = config.home.homeDirectory;
  conductorDirectory = "${config.xdg.dataHome}/agent-deck/conductor";
  logDirectory = "${config.xdg.dataHome}/agent-deck/logs";
  daemonPath = "${config.home.profileDirectory}/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  commonEnvironment = {
    HOME = homeDirectory;
    PATH = daemonPath;
    XDG_CONFIG_HOME = config.xdg.configHome;
    XDG_DATA_HOME = config.xdg.dataHome;
  };
in
{
  options.johnw.agentDeck.enableConductorDiscordBridge = lib.mkEnableOption ''
    the agent-deck conductor Discord bridge and transition notifier
  '';

  config = lib.mkIf cfg.enableConductorDiscordBridge {
    assertions = [
      {
        assertion = pkgs.stdenv.isDarwin;
        message = "The agent-deck conductor Discord bridge currently requires launchd";
      }
    ];

    # agent-deck prefers this conventional path when it renders its own plist.
    # The directory is a Nix Python environment, not a mutable virtualenv.
    xdg.dataFile."agent-deck/conductor/venv".source = bridgePython;

    # launchd opens log files before starting a job. Ensure both parents exist
    # after Home Manager links the Python environment and before it bootstraps
    # the agents.
    home.activation.prepareAgentDeckConductorDirectories =
      lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "linkGeneration" ]
        ''
          run ${pkgs.coreutils}/bin/install -d -m 0700 \
            ${lib.escapeShellArg conductorDirectory} \
            ${lib.escapeShellArg logDirectory}
        '';

    launchd.agents = {
      agent-deck-conductor-bridge = {
        enable = true;
        domain = "gui";
        config = {
          Label = "com.agentdeck.conductor-bridge";
          ProgramArguments = [
            "${conductorDirectory}/venv/bin/python3"
            "${conductorDirectory}/bridge.py"
          ];
          EnvironmentVariables = commonEnvironment // {
            AGENT_DECK_CONDUCTOR_DIR = conductorDirectory;
            PYTHONNOUSERSITE = "1";
            PYTHONUNBUFFERED = "1";
          };
          WorkingDirectory = homeDirectory;
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "${conductorDirectory}/bridge.log";
          StandardErrorPath = "${conductorDirectory}/bridge.log";
          ThrottleInterval = 10;
          LowPriorityIO = true;
        };
      };

      agent-deck-transition-notifier = {
        enable = true;
        domain = "gui";
        config = {
          Label = "com.agentdeck.transition-notifier";
          ProgramArguments = [
            "${agentDeck}/bin/agent-deck"
            "notify-daemon"
          ];
          EnvironmentVariables = commonEnvironment;
          WorkingDirectory = homeDirectory;
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "${logDirectory}/transition-notifier.log";
          StandardErrorPath = "${logDirectory}/transition-notifier.log";
          ThrottleInterval = 5;
        };
      };
    };
  };
}
