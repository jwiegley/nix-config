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

  dedicatedMode = (isLinux && cfg.useHeadlessEmacs) || (isDarwin && cfg.useDedicatedDarwinEmacs);

  anvilMcp = pkgs.callPackage ../packages/anvil-mcp {
    useHeadlessEmacs = isLinux && cfg.useHeadlessEmacs;
    useDedicatedDarwinEmacs = isDarwin && cfg.useDedicatedDarwinEmacs;
    inherit (cfg) usePerAgentDaemon;
  };
  clientToolTimeoutMilliseconds = 1000 * anvilMcp.timeoutPolicy.clientToolSeconds;
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
        In dedicated-Emacs mode, give each MCP bridge its own supervised
        headless Emacs daemon. Distinct Codex, Claude, and other agent bridge
        processes receive isolated roots and worker pools. Logical agents that
        share one client-side MCP byte stream necessarily share that bridge. A
        host-scoped service is installed only when this option is false.
      '';
    };
  };

  config = lib.mkMerge [
    { home.packages = [ anvilMcp ]; }

    (lib.mkIf dedicatedMode {
      # Claude reads this only at client startup.  The per-server rendered
      # timeout remains authoritative for GUI clients that do not inherit the
      # Home Manager session environment.  Preserve a larger user policy.
      home.sessionVariables.MCP_TIMEOUT = lib.mkDefault (toString clientToolTimeoutMilliseconds);
      assertions = [
        {
          assertion =
            let
              timeout = toString (config.home.sessionVariables.MCP_TIMEOUT or "");
            in
            builtins.match "[0-9]+" timeout != null && lib.toInt timeout >= clientToolTimeoutMilliseconds;
          message = "Dedicated Anvil requires MCP_TIMEOUT to be at least ${toString clientToolTimeoutMilliseconds} milliseconds";
        }
      ];
    })

    # Single-host compatibility services are an explicit fallback topology.
    # Per-agent launchers own their supervisors and install no global service.
    (lib.mkIf (isLinux && cfg.useHeadlessEmacs && !cfg.usePerAgentDaemon) {
      systemd.user.services.anvil-headless-emacs = {
        Unit.Description = "Legacy-compatible headless Emacs for Anvil MCP";
        Service = {
          ExecStart = "${anvilMcp}/bin/anvil-headless-emacs";
          Restart = "always";
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
            # Retry until any listener from the preceding generation exits,
            # then take over the same legacy socket without a service gap.
            ANVIL_EMACS_LOCK_CONFLICT_STATUS = "75";
            ANVIL_EMACS_USE_SYSTEM_LOG = "1";
          };
          RunAtLoad = true;
          KeepAlive = true;
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
