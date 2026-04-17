# Shared cross-platform home-manager module for John Wiegley.
#
# This is the single source of truth for johnw's user environment.
# It is imported by:
#   - Darwin hosts (hera, clio) via config/home.nix
#   - NixOS/Linux hosts (vulcan, vps, andoria) via their own thin wrappers
#
# Platform-specific settings use lib.mkIf pkgs.stdenv.isDarwin / isLinux.
# Host-specific settings use lib.mkIf (hostname == "...").
# Values that may need per-host override use lib.mkDefault.

{
  pkgs,
  lib,
  config,
  hostname,
  inputs,
  ...
}:
let
  inherit (pkgs.stdenv) isDarwin isLinux;

  # Shared variables - also imported by sub-modules
  vars = import ./vars.nix {
    inherit
      pkgs
      lib
      config
      hostname
      inputs
      ;
  };
in
{
  imports =
    # Extracted sub-modules for better organization
    [
      ./git.nix
      ./ssh.nix
      ./zsh.nix
      ./xdg-symlinks.nix
      ./email.nix
      ./launchd.nix
    ]
    # Conditional flake input modules
    ++ lib.optionals (inputs ? git-ai) [
      inputs.git-ai.homeManagerModules.default
    ]
    ++ lib.optionals (inputs ? promptdeploy) [
      inputs.promptdeploy.homeManagerModules.default
      # Configure promptdeploy here so the definition is absent when the
      # module (and its option declarations) is also absent.
      (
        { pkgs, lib, ... }:
        lib.mkIf pkgs.stdenv.isDarwin {
          programs.promptdeploy = {
            enable = true;
            package = inputs.promptdeploy.packages.${pkgs.stdenv.hostPlatform.system}.default;
            sourceDir = "${vars.home}/src/promptdeploy";
            targets = [ "local" ];
          };
        }
      )
    ];

  home = {
    stateVersion = lib.mkDefault "24.11";

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
      GRAPHVIZ_DOT = "${pkgs.graphviz}/bin/dot";
      GTAGSLABEL = "pygments";
      HOSTNAME = hostname;
      JAVA_OPTS = "-Xverify:none";
      LESSHISTFILE = "${config.xdg.cacheHome}/less/history";
      LITELLM_PROXY_URL = "http://litellm.vulcan.lan";
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

      RCLONE_PASSWORD_COMMAND = "${pkgs.pass}/bin/pass show Passwords/rclone";
      RESTIC_PASSWORD_COMMAND = "${pkgs.pass}/bin/pass show Passwords/restic";
      FILTER_BRANCH_SQUELCH_WARNING = "1";
      HF_HUB_ENABLE_HF_TRANSFER = "1";
      LLAMA_INDEX_CACHE_DIR = "${config.xdg.cacheHome}/llama-index";
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
      "${vars.home}/.local/bin"
    ]
    ++ lib.optionals isDarwin [
      "${vars.home}/work/positron/bin"
      "/usr/local/bin"
      "/usr/local/zfs/bin"
      "/opt/homebrew/bin"
      "/opt/homebrew/opt/node@22/bin"
    ];

    activation = { };

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
    // lib.optionalAttrs (inputs ? llm-agents) {
      ".local/bin/claude".source = config.lib.file.mkOutOfStoreSymlink "${
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
      }/bin/claude";
    }
    // lib.optionalAttrs (pkgs ? sherlock-db) {
      ".claude/skills/sherlock/SKILL.md".source = "${pkgs.sherlock-db}/share/sherlock/SKILL.md";
      ".claude/skills/sherlock/sherlock".source = "${pkgs.sherlock-db}/bin/sherlock";
    };
  };

  programs = {
    direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    git-ai = {
      enable = true;
      installHooks = true;
      settings = {
        promptStorage = "local";
        includePromptsInRepositories = [
          "ghpos:positron-ai/*"
          "*positron-ai*"
        ];
        defaultPromptStorage = "notes";
        featureFlags.asyncMode = false;
      };
    };

    carapace = lib.mkIf isDarwin {
      enable = true;
      enableZshIntegration = true;
    };

    htop.enable = true;
    info.enable = true;
    jq.enable = true;
    man.enable = true;
    vim.enable = true;

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
      mouse = lib.mkDefault true;
      terminal = "tmux-256color";
      escapeTime = 0;
      historyLimit = 250000;
      focusEvents = true;
      aggressiveResize = false;
      extraConfig = ''
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
      enable = true;
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
      enable = true;
      package = pkgs.pass.withExtensions (exts: [
        exts.pass-otp
        exts.pass-genphrase
      ]);
      settings.PASSWORD_STORE_DIR = "${vars.home}/doc/.password-store";
    };

    gpg = {
      enable = true;
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
  };

  services = lib.mkIf isDarwin {
    gpg-agent = {
      enable = true;
      enableSshSupport = true;
      defaultCacheTtl = 86400;
      maxCacheTtl = 86400;
      pinentry.package = pkgs.pinentry_mac;
    };
  };

  xdg = {
    enable = true;
    configFile = {
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
