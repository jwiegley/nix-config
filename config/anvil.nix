{
  config,
  lib,
  options,
  pkgs,
  ...
}:

let
  cfg = config.johnw.anvil;
  inherit (pkgs.stdenv) isDarwin isLinux;

  anvilMcp = pkgs.callPackage ../packages/anvil-mcp {
    useHeadlessEmacs = isLinux && cfg.useHeadlessEmacs;
    useDedicatedDarwinEmacs = isDarwin && cfg.useDedicatedDarwinEmacs;
    inherit (cfg) usePerAgentDaemon;
  };
  launchdAgentOptions =
    if options ? launchd && options.launchd ? agents then
      options.launchd.agents.type.nestedTypes.elemType.getSubOptions [ ]
    else
      { };
in
{
  options.johnw.anvil = {
    useHeadlessEmacs = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        On Linux, use a dedicated headless Emacs daemon for the complete
        configured Anvil tool surface. When false, use the Emacs-free
        NeLisp standalone backend.
      '';
    };

    useDedicatedDarwinEmacs = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        On Darwin, route Anvil through a dedicated headless Emacs daemon
        instead of the interactive development Emacs.
      '';
    };

    usePerAgentDaemon = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        In dedicated-Emacs mode, give each owning Codex OS process its own
        supervised headless Emacs daemon. The anvil and emacs-eval bridges,
        including internal subagents, share that process-local pool; separate
        Codex and agent-deck processes receive isolated pools.
      '';
    };
  };

  config = lib.mkMerge [
    {
      home.packages = [ anvilMcp ];
    }

    (lib.mkIf (isLinux && cfg.useHeadlessEmacs && !cfg.usePerAgentDaemon) {
      systemd.user.services.anvil-headless-emacs = {
        Unit.Description = "Dedicated headless Emacs for Anvil MCP";
        Service = {
          ExecStart = "${anvilMcp}/bin/anvil-headless-emacs";
          Restart = "on-failure";
          RestartPreventExitStatus = 75;
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
      };
    })

    (lib.mkIf (isDarwin && cfg.useDedicatedDarwinEmacs && !cfg.usePerAgentDaemon) {
      launchd.agents.anvil-headless-emacs = {
        enable = true;
        config = {
          ProgramArguments = [ "${anvilMcp}/bin/anvil-headless-emacs" ];
          EnvironmentVariables = {
            ANVIL_EMACS_LOCK_CONFLICT_STATUS = "0";
            ANVIL_EMACS_USE_SYSTEM_LOG = "1";
          };
          RunAtLoad = true;
          KeepAlive = {
            Crashed = true;
            SuccessfulExit = false;
          };
          ProcessType = "Standard";
          LowPriorityIO = false;
          LowPriorityBackgroundIO = false;
          ThrottleInterval = 10;
        };
      }
      // lib.optionalAttrs (launchdAgentOptions ? domain) {
        # Keychain-backed tools such as gh require the login GUI bootstrap
        # namespace. After activation, verify without exposing credentials:
        # launchctl print gui/$UID/org.nix-community.home.anvil-headless-emacs
        # and run gh auth status through Anvil's shell-run tool.
        domain = "gui";
      };
    })
  ];
}
