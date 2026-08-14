{
  darwinConfigurations,
  homeConfigurations,
  homeManagerLib,
  pkgs,
  stockDarwinPkgs,
}:

let
  inherit (pkgs) lib;
  hera = darwinConfigurations.hera.config.home-manager.users.johnw;
  clio = darwinConfigurations.clio.config.home-manager.users.johnw;
  darwinPkgs = darwinConfigurations.hera.pkgs;
  linuxConfigurations = [
    homeConfigurations."johnw@aarch64-linux"
    homeConfigurations."jwiegley@x86_64-linux"
  ];
  linuxPkgs = (builtins.head linuxConfigurations).pkgs;
  homeDirectory = hera.home.homeDirectory;
  conductorDirectory = "${hera.xdg.dataHome}/agent-deck/conductor";
  logDirectory = "${hera.xdg.dataHome}/agent-deck/logs";
  relativeToHome = path: lib.removePrefix "${homeDirectory}/" path;
  conductorRelative = relativeToHome conductorDirectory;
  logRelative = relativeToHome logDirectory;
  daemonPath = "${hera.home.profileDirectory}/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  activation = hera.home.activation.prepareAgentDeckConductorDirectories;
  bridgeVenv = hera.xdg.dataFile."agent-deck/conductor/venv".source;
  expectedBridgeVenv = darwinPkgs.python3.withPackages (
    pythonPackages: with pythonPackages; [
      discordpy
      toml
    ]
  );

  bridge = hera.launchd.agents.agent-deck-conductor-bridge or null;
  notifier = hera.launchd.agents.agent-deck-transition-notifier or null;
  validAgent = agent: agent.enable && agent.domain == "gui" && agent.waitForNixStore;
  validBridge =
    let
      cfg = bridge.config;
      environment = cfg.EnvironmentVariables;
    in
    bridge != null
    && validAgent bridge
    && cfg.Label == "com.agentdeck.conductor-bridge"
    &&
      cfg.ProgramArguments == [
        "${conductorDirectory}/venv/bin/python3"
        "${conductorDirectory}/bridge.py"
      ]
    && environment.HOME == homeDirectory
    && environment.PATH == daemonPath
    && environment.XDG_CONFIG_HOME == hera.xdg.configHome
    && environment.XDG_DATA_HOME == hera.xdg.dataHome
    && environment.AGENT_DECK_CONDUCTOR_DIR == conductorDirectory
    && environment.PYTHONNOUSERSITE == "1"
    && environment.PYTHONUNBUFFERED == "1"
    && cfg.WorkingDirectory == homeDirectory
    && cfg.RunAtLoad
    && lib.attrByPath [
      "KeepAlive"
      "PathState"
      "${conductorDirectory}/bridge.py"
    ] false cfg
    && cfg.StandardOutPath == "${conductorDirectory}/bridge.log"
    && cfg.StandardErrorPath == "${conductorDirectory}/bridge.log"
    && cfg.ThrottleInterval == 10
    && cfg.LowPriorityIO;
  validNotifier =
    let
      cfg = notifier.config;
      environment = cfg.EnvironmentVariables;
    in
    notifier != null
    && validAgent notifier
    && cfg.Label == "com.agentdeck.transition-notifier"
    &&
      cfg.ProgramArguments == [
        "${darwinPkgs.agent-deck}/bin/agent-deck"
        "notify-daemon"
      ]
    && environment.HOME == homeDirectory
    && environment.PATH == daemonPath
    && environment.XDG_CONFIG_HOME == hera.xdg.configHome
    && environment.XDG_DATA_HOME == hera.xdg.dataHome
    && cfg.WorkingDirectory == homeDirectory
    && cfg.RunAtLoad
    && cfg.KeepAlive
    && cfg.StandardOutPath == "${logDirectory}/transition-notifier.log"
    && cfg.StandardErrorPath == "${logDirectory}/transition-notifier.log"
    && cfg.ThrottleInterval == 5;

  agentDeckDataFiles =
    home: lib.filterAttrs (name: _: lib.hasPrefix "agent-deck/" name) home.xdg.dataFile;
  agentDeckAgents =
    home: lib.filterAttrs (name: _: lib.hasPrefix "agent-deck-" name) home.launchd.agents;
  hasAgentDeckPackage =
    agentDeck: home: builtins.any (package: package.drvPath == agentDeck.drvPath) home.home.packages;
  lifecycleAbsent =
    home:
    !home.johnw.agentDeck.enableConductorDiscordBridge
    && (agentDeckDataFiles home) == { }
    && (agentDeckAgents home) == { }
    && !(home.home.activation ? prepareAgentDeckConductorDirectories);
  configurationEvaluation =
    modulePkgs: enable:
    let
      configuration = homeManagerLib.homeManagerConfiguration {
        pkgs = modulePkgs;
        modules = [
          ../../config/agent-deck.nix
          {
            johnw.agentDeck.enableConductorDiscordBridge = enable;
            home = {
              username = "fixture";
              homeDirectory = "/home/fixture";
              stateVersion = "24.11";
            };
          }
        ];
      };
    in
    builtins.tryEval configuration.config.johnw.agentDeck.enableConductorDiscordBridge;
in
assert hera.johnw.agentDeck.enableConductorDiscordBridge;
assert lifecycleAbsent clio;
assert hasAgentDeckPackage darwinConfigurations.hera.pkgs.agent-deck hera;
assert hasAgentDeckPackage darwinConfigurations.clio.pkgs.agent-deck clio;
assert lib.hasPrefix "${homeDirectory}/" conductorDirectory;
assert lib.hasPrefix "${homeDirectory}/" logDirectory;
assert hera.xdg.dataFile ? "agent-deck/conductor/venv";
assert bridgeVenv.drvPath == expectedBridgeVenv.drvPath;
assert activation.before == [ "setupLaunchAgents" ];
assert activation.after == [ "linkGeneration" ];
assert validBridge;
assert validNotifier;
assert builtins.all (
  configuration: hasAgentDeckPackage configuration.pkgs.agent-deck configuration.config
) linuxConfigurations;
assert builtins.all (configuration: lifecycleAbsent configuration.config) linuxConfigurations;
assert stockDarwinPkgs.stdenv.hostPlatform.isDarwin;
assert !(stockDarwinPkgs ? agent-deck);
assert !linuxPkgs.stdenv.hostPlatform.isDarwin;
assert linuxPkgs ? agent-deck;
assert (configurationEvaluation darwinPkgs true).success;
assert (configurationEvaluation stockDarwinPkgs false).success;
assert !(configurationEvaluation stockDarwinPkgs true).success;
assert (configurationEvaluation linuxPkgs false).success;
assert !(configurationEvaluation linuxPkgs true).success;
pkgs.runCommand "agent-deck-home-manager-lifecycle" { } ''
  export HOME="$TMPDIR/home"
  configured_conductor=${lib.escapeShellArg conductorDirectory}
  configured_logs=${lib.escapeShellArg logDirectory}
  configured_install=${lib.escapeShellArg (builtins.unsafeDiscardStringContext "${darwinPkgs.coreutils}/bin/install")}
  conductor="$HOME/${conductorRelative}"
  logs="$HOME/${logRelative}"

  ${pkgs.coreutils}/bin/mkdir -p "$conductor" "$logs"
  ${pkgs.coreutils}/bin/chmod 0755 "$conductor" "$logs"
  printf '%s\n' 'mutable bridge' > "$conductor/bridge.py"
  printf '%s\n' 'mutable bridge log' > "$conductor/bridge.log"
  printf '%s\n' 'mutable conductor state' > "$conductor/state.db"
  printf '%s\n' 'mutable notifier log' > "$logs/transition-notifier.log"
  bridge_inode="$(${pkgs.coreutils}/bin/stat -c %i "$conductor/bridge.py")"
  state_inode="$(${pkgs.coreutils}/bin/stat -c %i "$conductor/state.db")"

  run() {
    if [ "$#" -ne 6 ] \
      || [ "$1" != "$configured_install" ] \
      || [ "$2" != -d ] \
      || [ "$3" != -m ] \
      || [ "$4" != 0700 ] \
      || [ "$5" != "$configured_conductor" ] \
      || [ "$6" != "$configured_logs" ]; then
      echo "unexpected Agent Deck directory activation" >&2
      return 1
    fi
    ${pkgs.coreutils}/bin/install -d -m 0700 "$conductor" "$logs"
  }

  if run "$configured_install" -d -m 0700 "$configured_conductor" "$HOME/unexpected" 2>/dev/null; then
    echo "Agent Deck activation accepted an unexpected target" >&2
    exit 1
  fi
  if run "$configured_install" -d -m 0700 "$configured_conductor" "$configured_logs" "$HOME/extra" 2>/dev/null; then
    echo "Agent Deck activation accepted an extra target" >&2
    exit 1
  fi

  ${builtins.unsafeDiscardStringContext activation.data}

  [ "$(${pkgs.coreutils}/bin/stat -c %a "$conductor")" = 700 ]
  [ "$(${pkgs.coreutils}/bin/stat -c %a "$logs")" = 700 ]
  [ "$bridge_inode" = "$(${pkgs.coreutils}/bin/stat -c %i "$conductor/bridge.py")" ]
  [ "$state_inode" = "$(${pkgs.coreutils}/bin/stat -c %i "$conductor/state.db")" ]
  [ "$(< "$conductor/bridge.py")" = 'mutable bridge' ]
  [ "$(< "$conductor/bridge.log")" = 'mutable bridge log' ]
  [ "$(< "$conductor/state.db")" = 'mutable conductor state' ]
  [ "$(< "$logs/transition-notifier.log")" = 'mutable notifier log' ]

  ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
    ${bridgeVenv}/bin/python3 -c 'import discord, toml'
  ''}

  touch "$out"
''
