# Shared cross-platform home-manager module for John Wiegley.
#
# This is the single source of truth for johnw's user environment.
# It is imported by:
#   - Darwin hosts (hera, clio) via config/home.nix
#   - NixOS/Linux hosts (vulcan, vps, andoria) via their own thin wrappers
#
# Platform-specific settings use lib.mkIf pkgs.stdenv.isDarwin / isLinux.
# Host-specific settings key off typed capability flags (config.johnw.host.*).
# Values that may need per-host override use lib.mkDefault.

args@{
  pkgs,
  lib,
  config,
  hostname,
  inputs,
  ...
}:
let
  inherit (pkgs.stdenv) isDarwin isLinux;
  nixManagedAiHomeClass = args.nixManagedAiHomeClass or null;
  isPositronRemoteLinux = isLinux && nixManagedAiHomeClass == "shared-work";
  isHeavy = config.johnw.profile.heavy;

  # Shared variables - also imported by sub-modules
  vars = import ./vars.nix {
    inherit
      pkgs
      config
      hostname
      inputs
      ;
  };
in
{
  _module.args.vars = vars;

  imports =
    # Extracted sub-modules for better organization
    [
      ./agent-deck.nix
      ./ai.nix
      ./fractal.nix
      ./git-options.nix
      ./host-options.nix
      ./git.nix
      ./ssh.nix
      ./zsh.nix
      ./xdg-symlinks.nix
      ./email.nix
    ]
    # Conditional flake input modules
    ++ lib.optionals (inputs ? git-ai) [
      inputs.git-ai.homeManagerModules.default
    ];

  home = {
    stateVersion = lib.mkDefault "24.11"; # overridden by wrappers; fallback only

    sessionVariables = {
      DISABLE_AUTOUPDATER = "1";
      B2_ACCOUNT_INFO = "${config.xdg.configHome}/backblaze-b2/account_info";
      CABAL_CONFIG = "${config.xdg.configHome}/cabal/config";
      CARGO_HOME = "${config.xdg.dataHome}/cargo";
      CLICOLOR = "yes";
      EDITOR = lib.mkDefault vars.emacsclient;
      EMACS_SERVER_FILE = "${vars.emacs-server}";
      EMAIL = vars.userEmail;
      ET_NO_TELEMETRY = "1";
      FONTCONFIG_FILE = "${config.xdg.configHome}/fontconfig/fonts.conf";
      FONTCONFIG_PATH = "${config.xdg.configHome}/fontconfig";
      GTAGSLABEL = "pygments";
      HOSTNAME = hostname;
      JAVA_OPTS = "-Xverify:none";
      LESSHISTFILE = "${config.xdg.cacheHome}/less/history";
      LLM_USER_PATH = "${config.xdg.configHome}/llm";
      NIX_CONF = "${vars.home}/src/nix";
      NLTK_DATA = "${config.xdg.dataHome}/nltk";
      PARALLEL_HOME = "${config.xdg.cacheHome}/parallel";
      PROFILE_DIR = "${config.home.profileDirectory}";
      RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
      SCREENRC = "${config.xdg.configHome}/screen/config";
      SSL_CERT_FILE = "${vars.ca-bundle_crt}";
      STARDICT_DATA_DIR = "${config.xdg.dataHome}/dictionary";
      TIKTOKEN_CACHE_DIR = "${config.xdg.cacheHome}/tiktoken";
      TRAVIS_CONFIG_PATH = "${config.xdg.configHome}/travis";
      TZ = lib.mkDefault "America/Los_Angeles";
      VAGRANT_HOME = "${config.xdg.dataHome}/vagrant";
      WWW_HOME = "${config.xdg.cacheHome}/w3m";

      FILTER_BRANCH_SQUELCH_WARNING = "1";
      HF_XET_HIGH_PERFORMANCE = "1";
      LLAMA_INDEX_CACHE_DIR = "${config.xdg.cacheHome}/llama-index";
    }
    // lib.optionalAttrs isHeavy {
      GRAPHVIZ_DOT = "${pkgs.graphviz}/bin/dot";
      RCLONE_PASSWORD_COMMAND = "${pkgs.pass}/bin/pass show Passwords/rclone";
      RESTIC_PASSWORD_COMMAND = "${pkgs.pass}/bin/pass show Passwords/restic";
    }
    // lib.optionalAttrs isDarwin {
      ASPELL_CONF = "conf ${config.xdg.configHome}/aspell/config;";
      EMACSVER = "30MacPort";
      GTAGSCONF = "${pkgs.global}/share/gtags/gtags.conf";
      NODE_EXTRA_CA_CERTS = "${config.xdg.configHome}/ragflow/root_ca.crt";
      VAGRANT_DEFAULT_PROVIDER = "vmware_desktop";
      VAGRANT_VMWARE_CLONE_DIRECTORY = "${vars.home}/Machines/vagrant";
      SSH_AUTH_SOCK = "${config.xdg.configHome}/gnupg/S.gpg-agent.ssh";
    }
    // lib.optionalAttrs isLinux {
      FACTORY_AUTO_UPDATE = "false";
    }
    // lib.optionalAttrs (!vars.gitAiEnabled) {
      GIT_AI_INSTALL_DEV_HOOKS = "0";
    };

    sessionSearchVariables = {
      MANPATH = [
        "${config.home.profileDirectory}/share/man"
        "${config.xdg.configHome}/.local/share/man"
        "/run/current-system/sw/share/man"
        "/usr/local/share/man"
        "/usr/share/man"
      ];
    };

    sessionPath = [
      "${vars.home}/src/scripts"
      "${config.home.profileDirectory}/bin"
      "${vars.home}/.local/bin"
    ]
    ++ lib.optionals isDarwin [
      "${vars.home}/work/positron/bin"
      "/usr/local/bin"
      "/usr/local/zfs/bin"
      "/opt/homebrew/bin"
      "/opt/homebrew/opt/node@22/bin"
    ];

    file = {
      ".ledgerrc".text = ''
        --file ${vars.home}/doc/accounts/main.ledger
        --input-date-format %Y/%m/%d
        --date-format %Y/%m/%d
      '';

      ".curlrc".text = ''
        capath=${vars.ca-bundle_path}
        cacert=${config.xdg.configHome}/curl/ca-bundle.crt
      '';

      ".wgetrc".text = ''
        ca_directory = ${vars.ca-bundle_path}
        ca_certificate = ${vars.ca-bundle_crt}
      '';
    }
    // lib.optionalAttrs isPositronRemoteLinux {
      ".local/bin/agent-deck-remote-env" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          # /tmp is tmux's native socket parent and survives non-PAM SSH sessions.
          export TMUX_TMPDIR="''${AGENTDECK_TMUX_TMPDIR:-/tmp}"
          export CLAUDE_CONFIG_DIR="$HOME/.claude"
          exec "$HOME/.nix-profile/bin/agent-deck" "$@"
        '';
      };
    }
    // lib.optionalAttrs (pkgs ? sherlock-db) {
      ".claude/skills/sherlock/SKILL.md".source = "${pkgs.sherlock-db}/share/sherlock/SKILL.md";
      ".claude/skills/sherlock/sherlock".source = "${pkgs.sherlock-db}/bin/sherlock";
    };

    # claude-mem needs the injection-free private command from the locally
    # patched Claude package. Its settings remain mutable, so update only the path.
    activation.claudeMemRealClaude = lib.mkIf (inputs ? llm-agents) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        cm_settings="${vars.home}/.claude-mem/settings.json"
        cm_claude="${config.home.profileDirectory}/bin/claude-real"
        if [ -f "$cm_settings" ]; then
          cm_cur="$(${pkgs.jq}/bin/jq -r '.CLAUDE_CODE_PATH // ""' "$cm_settings" 2>/dev/null || true)"
          if [ "$cm_cur" != "$cm_claude" ]; then
            cm_tmp="$(mktemp "$cm_settings.XXXXXX" 2>/dev/null || true)"
            if [ -n "$cm_tmp" ] && ${pkgs.jq}/bin/jq --arg p "$cm_claude" '.CLAUDE_CODE_PATH = $p' "$cm_settings" > "$cm_tmp" 2>/dev/null; then
              cm_mode="$(stat -c '%a' "$cm_settings" 2>/dev/null || stat -f '%Lp' "$cm_settings" 2>/dev/null || echo 644)"
              chmod "$cm_mode" "$cm_tmp"
              $DRY_RUN_CMD mv "$cm_tmp" "$cm_settings"
              echo "claude-mem: pinned CLAUDE_CODE_PATH -> $cm_claude"
            elif [ -n "$cm_tmp" ]; then
              rm -f "$cm_tmp"
            fi
          fi
        fi
      ''
    );
  };

  programs = {
    direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    carapace = lib.mkIf isDarwin {
      enable = true;
      enableZshIntegration = true;
    };

    htop.enable = true;
    info.enable = isHeavy;
    jq.enable = true;
    man.enable = true;
    vim.enable = isHeavy;

    zoxide = lib.mkIf isDarwin {
      enable = true;
      enableZshIntegration = true;
    };

    starship = {
      enable = true;
      settings = lib.mkMerge [
        (builtins.fromTOML (
          builtins.readFile "${pkgs.starship}/share/starship/presets/nerd-font-symbols.toml"
        ))
        {
          add_newline = true;
          scan_timeout = lib.mkDefault 50;
          follow_symlinks = false;
          command_timeout = lib.mkDefault 1000;

          format = lib.concatStrings [
            ''
              ($all
              )''
            "$directory"
            "$character"
          ];

          line_break.disabled = true;

          git_status.disabled = true;
        }
      ];

      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    tmux = {
      enable = true;
      # Detached fleet sessions must survive logout and non-PAM SSH invocations.
      secureSocket = false;
      mouse = lib.mkDefault true;
      terminal = "tmux-256color";
      escapeTime = 0;
      historyLimit = 250000;
      focusEvents = true;
      aggressiveResize = false;
      extraConfig = ''
        set-option -g prefix 'C-\'
        set-option -g allow-passthrough on
        set-option -g set-clipboard on
        set-option -g extended-keys off
        set-option -ga terminal-overrides ",xterm-256color:RGB"
        set-option -as terminal-features ",xterm-256color:sync:extkeys"
        set-option -g default-shell ${pkgs.zsh}/bin/zsh
        set-option -g default-command ${pkgs.zsh}/bin/zsh
      ''
      + lib.optionalString isDarwin ''

        set-option -g set-titles on
        set-option -g set-titles-string "#{b:pane_current_path}"

        set-option -g automatic-rename on
        set-option -g automatic-rename-format "#{b:pane_current_path}"
      '';
    };

    home-manager = {
      enable = true;
      path = lib.mkIf isDarwin "${vars.home}/src/nix/home-manager";
    };

    browserpass = {
      enable = isHeavy;
      browsers = [ "firefox" ];
    };

    texlive = lib.mkIf isDarwin {
      enable = true;
      extraPackages = tpkgs: {
        inherit (tpkgs) scheme-full texdoc latex2e-help-texinfo;
        pkgFilter = pkg: pkg.tlType == "run" || pkg.tlType == "bin" || pkg.pname == "latex2e-help-texinfo";
      };
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
      defaultOptions = [
        "--height 40%"
        "--layout=reverse"
        "--info=inline"
        "--border"
        "--exact"
      ];
    };

    password-store = {
      enable = isHeavy;
      package = pkgs.pass.withExtensions (exts: [
        exts.pass-otp
        exts.pass-genphrase
      ]);
      settings.PASSWORD_STORE_DIR = "${vars.home}/doc/.password-store";
    };

    gpg = {
      enable = isHeavy;
      homedir = "${config.xdg.configHome}/gnupg";
      settings = {
        use-agent = true;
        default-key = vars.master_key;
        auto-key-locate = "keyserver";
        keyserver = "keys.openpgp.org";
        keyserver-options = "no-honor-keyserver-url include-revoked auto-key-retrieve";
      };
      scdaemonSettings = {
        card-timeout = "1";
        disable-ccid = true;
      }
      // lib.optionalAttrs isDarwin {
        pcsc-driver = "/System/Library/Frameworks/PCSC.framework/PCSC";
      };
    };

    gh = {
      enable = true;
      settings = {
        editor = lib.mkDefault vars.emacsclient;
        git_protocol = "ssh";
        aliases = {
          co = "pr checkout";
          pv = "pr view";
          prs = "pr list -A jwiegley";
        };
      };
    };
  }
  // lib.optionalAttrs (inputs ? git-ai) {
    git-ai = {
      enable = isHeavy && vars.gitAiEnabled;
      installHooks = isHeavy && vars.gitAiEnabled;
      settings = {
        apiKeyFile = "${vars.home}/.git-ai/api-key";

        promptStorage = "local";
        includePromptsInRepositories = [
          "ghpos:positron-ai/*"
          "*positron-ai*"
        ];
        defaultPromptStorage = "notes";

        featureFlags = {
          # transcriptSweep is the only flag whose release default differs
          # from the debug default — enable here if you want it on in release:
          transcriptSweep = true;

          # Uncomment to override other flags from their release defaults:
          # rewriteStash = true;             # already true by default
          # authKeyring = false;             # already false by default
          # gitHooksEnabled = false;         # already false by default
          # gitHooksExternallyManaged = false; # already false by default
          # transcriptStreaming = true;      # already true by default
        };
      };
    };
  };

  launchd.agents = lib.mkIf isDarwin {
    # Preserve Home Manager's GPG configuration while nix-darwin owns startup.
    gpg-agent.enable = lib.mkForce false;
  };

  services = lib.mkIf isDarwin {
    gpg-agent = {
      enable = true;
      enableSshSupport = true;
      # Keep approved PINs until gpg-agent is explicitly killed.
      defaultCacheTtl = 2147483647;
      maxCacheTtl = 2147483647;
      pinentry.package = pkgs.pinentry_mac;
    };
  };

  xdg = {
    enable = true;
    configFile = lib.optionalAttrs isHeavy {
      "nix/nix.conf" = lib.mkIf isPositronRemoteLinux {
        text = ''
          cores = 32
          experimental-features = nix-command flakes
          extra-substituters = https://cache.iog.io
          substituters = https://cache.nixos.org https://tron.cachix.org
        '';
      };

      "aspell/config".text = ''
        local-data-dir ${pkgs.aspell}/lib/aspell
        data-dir ${pkgs.aspellDicts.en}/lib/aspell
        personal ${config.xdg.configHome}/aspell/en_US.personal
        repl ${config.xdg.configHome}/aspell/en_US.repl
      '';
    };
  };

  targets.darwin = lib.mkIf isDarwin {
    keybindings = {
      "~f" = "moveWordForward:";
      "~b" = "moveWordBackward:";

      "~d" = "deleteWordForward:";
      "~^h" = "deleteWordBackward:";

      "~v" = "pageUp:";
      "^v" = "pageDown:";

      "~&lt;" = "moveToBeginningOfDocument:";
      "~&gt;" = "moveToEndOfDocument:";

      "^/" = "undo:";
      "~/" = "complete:";

      "^g" = "_cancelKey:";
      "^a" = "moveToBeginningOfLine:";
      "^e" = "moveToEndOfLine:";

      "~c" = "capitalizeWord:";
      "~u" = "uppercaseWord:";
      "~l" = "lowercaseWord:";
      "^t" = "transpose:";
      "~t" = "transposeWords:";
    };

    defaults = {
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
    };
  };

  news.display = "silent";
}
