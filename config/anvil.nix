{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.johnw.anvil;
  inherit (pkgs.stdenv) isDarwin isLinux;

  anvilMcp = pkgs.callPackage ../packages/anvil-mcp {
    useHeadlessEmacs = isLinux && cfg.useHeadlessEmacs;
    useDedicatedDarwinEmacs = isDarwin && cfg.useDedicatedDarwinEmacs;
  };
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
  };

  config = lib.mkMerge [
    {
      home.packages = [ anvilMcp ];
    }

    (lib.mkIf (isLinux && cfg.useHeadlessEmacs) {
      systemd.user.services.anvil-headless-emacs = {
        Unit.Description = "Dedicated headless Emacs for Anvil MCP";
        Service = {
          ExecStart = "${anvilMcp}/bin/anvil-headless-emacs";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
      };
    })

    (lib.mkIf (isDarwin && cfg.useDedicatedDarwinEmacs) {
      launchd.agents.anvil-headless-emacs = {
        enable = true;
        domain = "user";
        config = {
          ProgramArguments = [ "${anvilMcp}/bin/anvil-headless-emacs" ];
          RunAtLoad = true;
          KeepAlive = {
            Crashed = true;
            SuccessfulExit = false;
          };
          ProcessType = "Standard";
          LowPriorityIO = false;
          LowPriorityBackgroundIO = false;
          ThrottleInterval = 10;
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/anvil-headless-emacs.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/anvil-headless-emacs.log";
        };
      };
    })
  ];
}
