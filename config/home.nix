{ pkgs, lib, config, hostname, inputs, ... }@args:

let home           = config.home.homeDirectory;
    tmpdir         = "/tmp";

    userName       = "John Wiegley";
    userEmail      = "johnw@newartisans.com";
    master_key     = "4710CF98AF9B327BB80F60E146C4BD1A7AC14BA2";
    signing_key    = "12D70076AB504679";

    external_host  = "home.newartisans.com";

    ca-bundle_path = "${pkgs.cacert}/etc/ssl/certs/";
    ca-bundle_crt  = "${ca-bundle_path}/ca-bundle.crt";
    emacs-server   = "${tmpdir}/johnw-emacs/server";
    emacsclient    = "${pkgs.emacs}/bin/emacsclient -s ${emacs-server}";
in {
  home = {
    stateVersion = "23.11";

    packages = import ./packages.nix args;

    sessionVariables = {
      ASPELL_CONF        = "conf ${config.xdg.configHome}/aspell/config;";
      B2_ACCOUNT_INFO    = "${config.xdg.configHome}/backblaze-b2/account_info";
      CABAL_CONFIG       = "${config.xdg.configHome}/cabal/config";
      CARGO_HOME         = "${config.xdg.dataHome}/cargo";
      CLICOLOR           = "yes";
      EDITOR             = "${emacsclient}";
      EMACSVER           = "30MacPort";
      EMACS_SERVER_FILE  = "${emacs-server}";
      EMAIL              = "${userEmail}";
      FONTCONFIG_FILE    = "${config.xdg.configHome}/fontconfig/fonts.conf";
      FONTCONFIG_PATH    = "${config.xdg.configHome}/fontconfig";
      GRAPHVIZ_DOT       = "${pkgs.graphviz}/bin/dot";
      GTAGSCONF          = "${pkgs.global}/share/gtags/gtags.conf";
      GTAGSLABEL         = "pygments";
      HOSTNAME           = hostname;
      JAVA_OPTS          = "-Xverify:none";
      LESSHISTFILE       = "${config.xdg.cacheHome}/less/history";
      LITELLM_PROXY_URL  = "http://vulcan/litellm";
      LLM_USER_PATH      = "${config.xdg.configHome}/llm";
      NIX_CONF           = "${home}/src/nix";
      NLTK_DATA          = "${config.xdg.dataHome}/nltk";
      PARALLEL_HOME      = "${config.xdg.cacheHome}/parallel";
      PROFILE_DIR        = "${config.home.profileDirectory}";
      RUSTUP_HOME        = "${config.xdg.dataHome}/rustup";
      SCREENRC           = "${config.xdg.configHome}/screen/config";
      SSL_CERT_FILE      = "${ca-bundle_crt}";
      STARDICT_DATA_DIR  = "${config.xdg.dataHome}/dictionary";
      TIKTOKEN_CACHE_DIR = "${config.xdg.cacheHome}/tiktoken";
      TRAVIS_CONFIG_PATH = "${config.xdg.configHome}/travis";
      TZ                 = "PST8PDT";
      VAGRANT_HOME       = "${config.xdg.dataHome}/vagrant";
      WWW_HOME           = "${config.xdg.cacheHome}/w3m";

      RCLONE_PASSWORD_COMMAND        = "${pkgs.pass}/bin/pass show Passwords/rclone";
      RESTIC_PASSWORD_COMMAND        = "${pkgs.pass}/bin/pass show Passwords/restic";
      VAGRANT_DEFAULT_PROVIDER       = "vmware_desktop";
      VAGRANT_VMWARE_CLONE_DIRECTORY = "${home}/Machines/vagrant";
      FILTER_BRANCH_SQUELCH_WARNING  = "1";
      HF_HUB_ENABLE_HF_TRANSFER      = "1";
      LLAMA_INDEX_CACHE_DIR          = "${config.xdg.cacheHome}/llama-index";

      # This forces clearing the variable so home-manager can set it
      SSH_AUTH_SOCK = "";
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
      "/usr/local/bin"
      "/opt/homebrew/bin"
      "${home}/.local/bin"
      # "${config.xdg.dataHome}/lmstudio/bin"
    ];

    file =
      let mkLink = config.lib.file.mkOutOfStoreSymlink; in {
        ".ledgerrc".text = ''
          --file ${home}/doc/accounts/main.ledger
          --input-date-format %Y/%m/%d
          --date-format %Y/%m/%d
        '';

        ".curlrc".text = ''
          capath=${ca-bundle_path}
          cacert=${ca-bundle_crt}
        '';

        ".wgetrc".text = ''
          ca_directory = ${ca-bundle_path}
          ca_certificate = ${ca-bundle_crt}
        '';

        ".aider".source        = mkLink "${config.xdg.configHome}/aider";
        ".cups".source         = mkLink "${config.xdg.configHome}/cups";
        ".claude".source       = mkLink "${config.xdg.configHome}/claude";
        ".cursor".source       = mkLink "${config.xdg.configHome}/cursor";
        ".dbvis".source        = mkLink "${config.xdg.configHome}/dbvis";
        ".gist".source         = mkLink "${config.xdg.configHome}/gist/api_key";
        ".jupyter".source      = mkLink "${config.xdg.configHome}/jupyter";
        ".kube".source         = mkLink "${config.xdg.configHome}/kube";
        ".mitmproxy".source    = mkLink "${config.xdg.configHome}/mitmproxy";
        ".sage".source         = mkLink "${config.xdg.configHome}/sage";
        ".jq".source           = mkLink "${config.xdg.configHome}/jq/config";
        ".mbsyncrc".source     = mkLink "${config.xdg.configHome}/mbsync/config";
        ".parallel".source     = mkLink "${config.xdg.configHome}/parallel";

        ".diffusionbee".source = mkLink "${config.xdg.dataHome}/diffusionbee";
        ".docker".source       = mkLink "${config.xdg.dataHome}/docker";
        ".vscode".source       = mkLink "${config.xdg.dataHome}/vscode";
        ".w3m".source          = mkLink "${config.xdg.dataHome}/w3m";
        ".wget-hsts".source    = mkLink "${config.xdg.dataHome}/wget/hsts";

        ".thinkorswim".source  = mkLink "${config.xdg.cacheHome}/thinkorswim";

        ".emacs.d".source      = mkLink "${home}/src/dot-emacs";
        "dl".source            = mkLink "${home}/Downloads";

        "News".source          = mkLink "${config.xdg.dataHome}/gnus/News";
      }
      // lib.optionalAttrs (hostname == "hera") {
        "Audio".source  = mkLink "/Volumes/ext/Audio";
        "Photos".source = mkLink "/Volumes/ext/Photos";
      }
      // lib.optionalAttrs (hostname == "clio") {
        "Audio".source  = mkLink "${home}/Library/CloudStorage/ShellFish/Hera/Audio";
        "Photos".source = mkLink "${home}/Library/CloudStorage/ShellFish/Hera/Photos";
        "Hera".source   = mkLink "${home}/Library/CloudStorage/ShellFish/Hera";
      }
      // lib.optionalAttrs (hostname == "hera" || hostname == "clio") {
        "org".source    = mkLink "${home}/doc/org";

        "Mobile".source =
          mkLink "${home}/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org";
        "Drafts".source =
          mkLink "${home}/Library/Mobile Documents/iCloud~com~agiletortoise~Drafts5/Documents";
        "Inbox".source  =
          mkLink "${home}/Library/Application Support/DEVONthink/Inbox";
        "iCloud".source        =
          mkLink "${home}/Library/Mobile Documents/com~apple~CloudDocs";

        "Video".source  = mkLink "${home}/Library/CloudStorage/ShellFish/Vulcan/Video";
        "Media".source  = mkLink "${home}/Library/CloudStorage/ShellFish/Vulcan/Media";
        "Vulcan".source = mkLink "${home}/Library/CloudStorage/ShellFish/Vulcan";
      };

      # activation.firefoxWriteBoundary =
      #   let
      #     profilesFilePath = "$HOME/Library/Application\\ Support/Firefox/profiles.ini";
      #   in lib.hm.dag.entryAfter
      #     [
      #       "writeBoundary"
      #       "linkGeneration"
      #     ]
      #     ''
      #       run mv ${profilesFilePath} ${profilesFilePath}.hm
      #       run cp "`readlink ${profilesFilePath}.hm`" ${profilesFilePath}
      #       run rm -f ${profilesFilePath}.$HOME_MANAGER_BACKUP_EXT
      #       run chmod u+w ${profilesFilePath}
      #     '';
  };

  accounts.email = {
    certificatesFile = ca-bundle_crt;

    accounts.fastmail = {
      realName = userName;
      address = userEmail;
      aliases = [
        "jwiegley@gmail.com"
        "johnw@gnu.org"
        "john@kadena.io"
        "john.wiegley@coppertogold.org"
      ];
      flavor = "fastmail.com";
      passwordCommand = "${pkgs.pass}/bin/pass show smtp.fastmail.com";
      primary = true;
      imap = {
        tls = {
          enable = true;
          useStartTls = false;
        };
      };
      smtp = {
        tls = {
          enable = true;
          useStartTls = true;
        };
      };
      gpg = {
        key = signing_key;
        signByDefault = false;
        encryptByDefault = false;
      };
    };
  };

  programs = {
    direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    htop.enable = true;
    info.enable = true;
    jq.enable = true;
    man.enable = true;
    vim.enable = true;

    # firefox = import ./firefox.nix { inherit hostname home pkgs; };

    starship = {
      enable = true;
      settings = {
        add_newline = true;

        # format = lib.concatStrings [
        #   "$hostname"
        #   "$directory"
        #   "$git_branch"
        #   "$git_state"
        #   "$git_status"
        #   "$cmd_duration"
        #   "$line_break"
        #   "$character"
        # ];

        scan_timeout = 10;
        # character = {
        #   success_symbol = "[➜](bold green)";
        #   error_symbol = "[➜](bold red)";
        # };

        aws.symbol            = "  ";
        buf.symbol            = " ";
        c.symbol              = " ";
        cmake.symbol          = " ";
        conda.symbol          = " ";
        crystal.symbol        = " ";
        dart.symbol           = " ";
        directory.read_only   = " 󰌾";
        docker_context.symbol = " ";
        elixir.symbol         = " ";
        elm.symbol            = " ";
        fennel.symbol         = " ";
        fossil_branch.symbol  = " ";
        git_branch.symbol     = " ";
        git_commit.tag_symbol = "  ";
        golang.symbol         = " ";
        guix_shell.symbol     = " ";
        haskell.symbol        = " ";
        haxe.symbol           = " ";
        hg_branch.symbol      = " ";
        hostname.ssh_symbol   = " ";
        java.symbol           = " ";
        julia.symbol          = " ";
        kotlin.symbol         = " ";
        lua.symbol            = " ";
        memory_usage.symbol   = "󰍛 ";
        meson.symbol          = "󰔷 ";
        nim.symbol            = "󰆥 ";
        nix_shell.symbol      = " ";
        nodejs.symbol         = " ";
        ocaml.symbol          = " ";
        package.symbol        = "󰏗 ";
        perl.symbol           = " ";
        php.symbol            = " ";
        pijul_channel.symbol  = " ";
        python.symbol         = " ";
        rlang.symbol          = "󰟔 ";
        ruby.symbol           = " ";
        rust.symbol           = "󱘗 ";
        scala.symbol          = " ";
        swift.symbol          = " ";
        zig.symbol            = " ";
        gradle.symbol         = " ";

        os.symbols = {
          Alpaquita        = " ";
          Alpine           = " ";
          AlmaLinux        = " ";
          Amazon           = " ";
          Android          = " ";
          Arch             = " ";
          Artix            = " ";
          CachyOS          = " ";
          CentOS           = " ";
          Debian           = " ";
          DragonFly        = " ";
          Emscripten       = " ";
          EndeavourOS      = " ";
          Fedora           = " ";
          FreeBSD          = " ";
          Garuda           = "󰛓 ";
          Gentoo           = " ";
          HardenedBSD      = "󰞌 ";
          Illumos          = "󰈸 ";
          Kali             = " ";
          Linux            = " ";
          Mabox            = " ";
          Macos            = " ";
          Manjaro          = " ";
          Mariner          = " ";
          MidnightBSD      = " ";
          Mint             = " ";
          NetBSD           = " ";
          NixOS            = " ";
          Nobara           = " ";
          OpenBSD          = "󰈺 ";
          openSUSE         = " ";
          OracleLinux      = "󰌷 ";
          Pop              = " ";
          Raspbian         = " ";
          Redhat           = " ";
          RedHatEnterprise = " ";
          RockyLinux       = " ";
          Redox            = "󰀘 ";
          Solus            = "󰠳 ";
          SUSE             = " ";
          Ubuntu           = " ";
          Unknown          = " ";
          Void             = " ";
          Windows          = "󰍲 ";
        };
      };
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    tmux = {
      enable = true;
      extraConfig = ''
        set-option -g allow-passthrough on
        set-option -g default-shell /bin/zsh
        set-option -g default-command /bin/zsh
        set-option -g history-limit 250000
      '';
    };

    home-manager = {
      enable = true;
      path = "${home}/src/nix/home-manager";
    };

    browserpass = {
      enable = true;
      browsers = [ "firefox" ];
    };

    texlive = {
      enable = true;
      extraPackages = tpkgs: {
        inherit (tpkgs) scheme-full texdoc latex2e-help-texinfo;
        pkgFilter = pkg:
             pkg.tlType == "run"
          || pkg.tlType == "bin"
          || pkg.pname == "latex2e-help-texinfo";
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

    bash = {
      enable = true;
      bashrcExtra = lib.mkBefore ''
        source /etc/bashrc
      '';
    };

    zsh = rec {
      dotDir = "${config.xdg.configHome}/zsh";

      enable = true;
      enableCompletion = false;

      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      history = {
        size       = 50000;
        save       = 500000;
        path       = "${config.xdg.configHome}/zsh/history";
        ignoreDups = true;
        share      = false;
        extended   = true;
      };

      sessionVariables = {
        ALTERNATE_EDITOR = "${pkgs.vim}/bin/vi";
        LC_CTYPE         = "en_US.UTF-8";
        LEDGER_COLOR     = "true";
        LESS             = "-FRSXM";
        LESSCHARSET      = "utf-8";
        PAGER            = "less";
        TINC_USE_NIX     = "yes";
        WORDCHARS        = "";

        ZSH_THEME_GIT_PROMPT_CACHE = "yes";
        ZSH_THEME_GIT_PROMPT_CHANGED = "%{$fg[yellow]%}%{✚%G%}";
        ZSH_THEME_GIT_PROMPT_STASHED = "%{$fg_bold[yellow]%}%{⚑%G%}";
        ZSH_THEME_GIT_PROMPT_UPSTREAM_FRONT =" {%{$fg[yellow]%}";

        ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX = "YES";
      };

      localVariables = {
        RPROMPT        = "%F{green}%~%f";
        PROMPT         = "%B%m %b\\$(git_super_status)%(!.#.$) ";
        PROMPT_DIRTRIM = "2";
      };

      shellAliases = {
        vi     = "${pkgs.vim}/bin/vim";
        b      = "${pkgs.git}/bin/git b";
        l      = "${pkgs.git}/bin/git l";
        w      = "${pkgs.git}/bin/git w";
        # g      = "${pkgs.gitAndTools.hub}/bin/hub";
        # git    = "${pkgs.gitAndTools.hub}/bin/hub";
        ga     = "${pkgs.gitAndTools.git-annex}/bin/git-annex";
        good   = "${pkgs.git}/bin/git bisect good";
        bad    = "${pkgs.git}/bin/git bisect bad";
        # ls     = "${pkgs.coreutils}/bin/ls --color=auto";
        # ls     = "${pkgs.eza}/bin/eza";
        # find   = "${pkgs.fd}/bin/fd";
        par    = "${pkgs.parallel}/bin/parallel";
        rm     = "${pkgs.rmtrash}/bin/rmtrash";
        rX     = "${pkgs.coreutils}/bin/chmod -R ugo+rX";
        scp    = "${pkgs.rsync}/bin/rsync -aP --inplace";
        wipe   = "${pkgs.srm}/bin/srm -vfr";
        switch = "${pkgs.nix-scripts}/bin/u ${hostname} switch";
        proc   = "${pkgs.darwin.ps}/bin/ps axwwww | ${pkgs.gnugrep}/bin/grep -i";
        nstat  = "${pkgs.darwin.network_cmds}/bin/netstat -nr -f inet"
               + " | ${pkgs.gnugrep}/bin/egrep -v \"(lo0|vmnet|169\\.254|255\\.255)\""
               + " | ${pkgs.coreutils}/bin/tail -n +5";

        # Use whichever cabal is on the PATH.
        cb     = "cabal build";
        cn     = "cabal configure --enable-tests --enable-benchmarks";
        cnp    = "cabal configure --enable-tests --enable-benchmarks " +
                 "--enable-profiling --ghc-options=-fprof-auto";

        rehash = "hash -r";
      };

      profileExtra = ''
        . ${pkgs.z}/share/z.sh
        setopt extended_glob
      '';

      initContent = ''
        # Make sure that fzf does not override the meaning of ^T
        bindkey '^T' transpose-chars

        if [[ $TERM == dumb || $TERM == emacs || ! -o interactive ]]; then
            unsetopt zle
            unset zle_bracketed_paste
            export PROMPT='$ '
            export RPROMPT=""
            export PS1='$ '
        else
            . ${config.xdg.configHome}/zsh/plugins/iterm2_shell_integration
            . ${pkgs.zsh-git-prompt}/share/zsh-git-prompt/zshrc.sh

            # sudo /bin/launchctl limit maxfiles 524288 524288
            # ulimit -n 65536

            autoload -Uz compinit
            compinit
        fi
      '';

      plugins = [
        {
          name = "iterm2_shell_integration";
          src = pkgs.fetchurl {
            url = https://iterm2.com/shell_integration/zsh;
            sha256 = "0yhfnaigim95sk1idrc3hpwii8hfhjl5m3lyc0ip3vi1a9npq0li";
            # date = 2025-03-19T15:01:02-0700;
          };
        }
      ];
    };

    password-store = {
      enable = true;
      package = pkgs.pass.withExtensions (exts: [
        exts.pass-otp
        exts.pass-genphrase
        # exts.pass-import
      ]);
      settings.PASSWORD_STORE_DIR = "${home}/doc/.password-store";
    };

    gpg = {
      enable = true;
      homedir = "${config.xdg.configHome}/gnupg";
      settings = {
        use-agent = true;
        default-key = master_key;
        auto-key-locate = "keyserver";
        keyserver = "keys.openpgp.org";
        keyserver-options = "no-honor-keyserver-url include-revoked auto-key-retrieve";
      };
      scdaemonSettings = {
        card-timeout = "1";
        disable-ccid = true;
        pcsc-driver = "/System/Library/Frameworks/PCSC.framework/PCSC";
      };
    };

    gh = {
      enable = true;
      settings = {
        editor = emacsclient;
        git_protocol = "ssh";
        aliases = {
          co = "pr checkout";
          pv = "pr view";
          prs = "pr list -A jwiegley";
        };
      };
    };

    git = {
      enable = true;
      # package = pkgs.gitFull;

      inherit userName userEmail;

      signing = {
        key = signing_key;
        signByDefault = true;
      };

      aliases = {
        amend      = "commit --amend -C HEAD";
        authors    = "!\"${pkgs.git}/bin/git log --pretty=format:%aN"
                   + " | ${pkgs.coreutils}/bin/sort"
                   + " | ${pkgs.coreutils}/bin/uniq -c"
                   + " | ${pkgs.coreutils}/bin/sort -rn\"";
        b          = "branch --color -v";
        ca         = "commit --amend";
        changes    = "diff --name-status -r";
        clone      = "clone --recursive";
        co         = "checkout";
        cp         = "cherry-pick";
        dc         = "diff --cached";
        dh         = "diff HEAD";
        ds         = "diff --staged";
        from       = "!${pkgs.git}/bin/git bisect start && ${pkgs.git}/bin/git bisect bad HEAD && ${pkgs.git}/bin/git bisect good";
        ls-ignored = "ls-files --exclude-standard --ignored --others";
        rc         = "rebase --continue";
        rh         = "reset --hard";
        ri         = "rebase --interactive";
        rs         = "rebase --skip";
        ru         = "remote update --prune";
        snap       = "!${pkgs.git}/bin/git stash"
                   + " && ${pkgs.git}/bin/git stash apply";
        snaplog    = "!${pkgs.git}/bin/git log refs/snapshots/refs/heads/"
                   + "\$(${pkgs.git}/bin/git rev-parse HEAD)";
        spull      = "!${pkgs.git}/bin/git stash"
                   + " && ${pkgs.git}/bin/git pull"
                   + " && ${pkgs.git}/bin/git stash pop";
        su         = "submodule update --init --recursive";
        undo       = "reset --soft HEAD^";
        w          = "status -sb";
        wdiff      = "diff --color-words";
        l          = "log --graph --pretty=format:'%Cred%h%Creset"
                   + " —%Cblue%d%Creset %s %Cgreen(%cr)%Creset'"
                   + " --abbrev-commit --date=relative --show-notes=*";
      };

      extraConfig = {
        core = {
          editor            = emacsclient;
          trustctime        = false;
          pager             = "${pkgs.less}/bin/less --tabs=4 -RFX";
          logAllRefUpdates  = true;
          precomposeunicode = false;
          whitespace        = "trailing-space,space-before-tab";
        };

        branch.autosetupmerge  = true;
        commit.gpgsign         = true;
        commit.status          = false;
        github.user            = "jwiegley";
        credential.helper      = "${pkgs.pass-git-helper}/bin/pass-git-helper";
        ghi.token              = "!${pkgs.pass}/bin/pass show api.github.com | head -1";
        hub.protocol           = "${pkgs.openssh}/bin/ssh";
        mergetool.keepBackup   = true;
        pull.rebase            = true;
        rebase.autosquash      = true;
        rerere.enabled         = false;
        init.defaultBranch     = "main";

        "merge \"ours\"".driver   = true;
        "magithub \"ci\"".enabled = false;

        http = {
          sslCAinfo = ca-bundle_crt;
          sslverify = true;
        };

        color = {
          status      = "auto";
          diff        = "auto";
          branch      = "auto";
          interactive = "auto";
          ui          = "auto";
          sh          = "auto";
        };

        push = {
          default = "tracking";
          # recurseSubmodules = "check";
        };

        "merge \"merge-changelog\"" = {
          name = "GNU-style ChangeLog merge driver";
          driver = "${pkgs.git-scripts}/bin/git-merge-changelog %O %A %B";
        };

        merge = {
          conflictstyle = "diff3";
          stat = true;
        };

        "color \"sh\"" = {
          branch      = "yellow reverse";
          workdir     = "blue bold";
          dirty       = "red";
          dirty-stash = "red";
          repo-state  = "red";
        };

        annex = {
          backends = "BLAKE2B512E";
          alwayscommit = false;
        };

        "filter \"media\"" = {
          required = true;
          clean = "${pkgs.git}/bin/git media clean %f";
          smudge = "${pkgs.git}/bin/git media smudge %f";
        };

        # submodule = {
        #   recurse = true;
        # };

        diff = {
          ignoreSubmodules = "dirty";
          renames = "copies";
          mnemonicprefix = true;
        };

        advice = {
          statusHints = false;
          pushNonFastForward = false;
          objectNameWarning = "false";
        };

        "filter \"lfs\"" = {
          clean = "${pkgs.git-lfs}/bin/git-lfs clean -- %f";
          smudge = "${pkgs.git-lfs}/bin/git-lfs smudge --skip -- %f";
          required = true;
        };

        "url \"git://github.com/ghc/packages-\"".insteadOf = "git://github.com/ghc/packages/";
        "url \"http://github.com/ghc/packages-\"".insteadOf = "http://github.com/ghc/packages/";
        "url \"https://github.com/ghc/packages-\"".insteadOf = "https://github.com/ghc/packages/";
        "url \"ssh://git@github.com/ghc/packages-\"".insteadOf = "ssh://git@github.com/ghc/packages/";
        "url \"git@github.com:/ghc/packages-\"".insteadOf = "git@github.com:/ghc/packages/";
      };

      ignores = [
        "#*#"
        "*.a"
        "*.agdai"
        "*.aux"
        "*.dylib"
        "*.elc"
        "*.glob"
        "*.hi"
        "*.la"
        "*.lia.cache"
        "*.lra.cache"
        "*.nia.cache"
        "*.nra.cache"
        "*.o"
        "*.so"
        "*.v.d"
        "*.v.tex"
        "*.vio"
        "*.vo"
        "*.vok"
        "*.vos"
        "*~"
        ".*.aux"
        ".Makefile.d"
        ".clean"
        ".coq-native/"
        ".coqdeps.d"
        ".direnv/"
        ".envrc"
        ".envrc.cache"
        ".envrc.override"
        ".ghc.environment.x86_64-darwin-*"
        ".makefile"
        ".pact-history"
        "TAGS"
        "cabal.project.local*"
        "default.hoo"
        "default.warn"
        "dist-newstyle/"
        "ghc[0-9]*_[0-9]*/"
        "input-haskell-*.tar.gz"
        "input-haskell-*.txt"
        "result"
        "result-*"
        "tags"
      ];
    };

    ssh = {
      enable = true;

      controlMaster       = "auto";
      controlPath         = "${tmpdir}/ssh-%u-%r@%h:%p";
      controlPersist      = "1800";
      forwardAgent        = true;
      serverAliveInterval = 60;
      hashKnownHosts      = true;
      userKnownHostsFile  = "${config.xdg.configHome}/ssh/known_hosts";

      matchBlocks =
        let
          withIdentity = attrs: attrs // {
            identityFile   = "${home}/${hostname}/id_${hostname}";
            identitiesOnly = true;
          };

          matchHost = host: hostname: {
            inherit hostname;
            match = ''
              host ${host} exec "${pkgs.unixtools.ping}/bin/ping -c1 -W50 -n -r -q ${hostname} > /dev/null 2>&1"
            '';
          };

          onHost = proxyJump: hostname: { inherit hostname; } //
            lib.optionalAttrs (hostname != proxyJump) {
              inherit proxyJump;
            };

          localBind = port: {
            bind = { inherit port; };
            host = { inherit port; address = "127.0.0.1"; };
          };
        in rec {

        # Hera

        hera_thunderbolt = lib.hm.dag.entryBefore ["hera"]
          (withIdentity (matchHost "hera" "192.168.2.1") // {
             hostname = "192.168.2.1";
             compression = false;
           });

        hera = withIdentity {
          hostname = "192.168.50.5";
          compression = false;
        };

        deimos  = withIdentity (onHost "hera" "192.168.221.128");
        simon   = withIdentity (onHost "hera" "172.16.194.158");
        minerva = withIdentity (onHost "hera" "192.168.50.117");

        # Athena

        athena = withIdentity {
          hostname = "192.168.50.235";
          compression = false;
        };

        phobos = withIdentity (onHost "athena" "192.168.50.111");

        # Clio

        clio_thunderbolt = lib.hm.dag.entryBefore ["clio"]
          (withIdentity (matchHost "clio" "192.168.2.2") // {
             compression = false;
           });

        clio = withIdentity {
          hostname = "192.168.50.112";
          compression = false;
        };

        neso = withIdentity (onHost "clio" "192.168.100.130");

        # Vulcan

        vulcan = withIdentity {
          user = "root";
          hostname = "192.168.50.182";
          compression = false;
        };

        tank = vulcan;

        # Other servers

        router = {
          hostname = "192.168.50.1";
          user = "router";
          compression = false;
        };

        elpa = { hostname = "elpa.gnu.org"; user = "root"; };
        savannah.hostname  = "git.sv.gnu.org";
        fencepost.hostname = "fencepost.gnu.org";

        savannah_gnu_org = withIdentity {
          host = lib.concatStringsSep " " [
            "git.savannah.gnu.org"
            "git.sv.gnu.org"
            "git.savannah.nongnu.org"
            "git.sv.nongnu.org"
          ];
        };

        haskell_org = {
          host           = "*haskell.org";
          user           = "root";
          identityFile   = "${config.xdg.configHome}/ssh/id_haskell";
          identitiesOnly = true;
        };
        mail.hostname = "mail.haskell.org";

        hf = withIdentity {
          host = "hf.co";
          user = "git";
        };

        # Kadena

        chainweb_com = {
          host           = "*.chainweb.com";
          user           = "chainweb";
          identityFile   = "${config.xdg.configHome}/ssh/id_kadena";
          identitiesOnly = true;
          extraOptions   = {
            StrictHostKeyChecking = "no";
          };
        };

        keychain = {
          host = "*";
          extraOptions = {
            UseKeychain    = "yes";
            AddKeysToAgent = "yes";
            IgnoreUnknown  = "UseKeychain";
          };
        };
      };
    };
  };

  services = {
    gpg-agent = {
      enable = true;
      enableSshSupport = true;
      defaultCacheTtl = 86400;
      maxCacheTtl = 86400;
      # pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
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

      "mbsync/config".text = ''
        IMAPAccount gmail-account
        Host imap.gmail.com
        User carmichaellsa@gmail.com
        PassCmd "pass mbsync.carmichael.imap.gmail.com"
        TLSType IMAPS
        AuthMechs LOGIN
        CertificateFile ${ca-bundle_crt}
        Port 993
        PipelineDepth 1

        IMAPStore gmail-remote
        Account gmail-account
        PathDelimiter /

        IMAPAccount dovecot
        TLSType None
        Host localhost
        Port 9143
        User johnw
        Pass pass
        AuthMechs PLAIN
        Tunnel "${pkgs.dovecot}/libexec/dovecot/imap -c /etc/dovecot/dovecot.conf"

        IMAPStore dovecot-local
        Account dovecot
        PathDelimiter .
        Trash mail.trash

        Channel assembly
        Far :gmail-remote:
        Near :dovecot-local:
        Patterns * !"[Gmail]/All Mail" !"[Gmail]/Important" !"[Gmail]/Starred" !"[Gmail]/Bin"
        Create Near
        Expunge None
        Remove None
        CopyArrivalDate yes
        Sync Pull New

        Group assembly
        Channel assembly
      '';
    };
  };

  targets.darwin = {
    keybindings = {
      "~f"    = "moveWordForward:";
      "~b"    = "moveWordBackward:";

      "~d"    = "deleteWordForward:";
      "~^h"   = "deleteWordBackward:";
      # "~\010" = "deleteWordBackward:";
      # "~\177" = "deleteWordBackward:";

      "~v"    = "pageUp:";
      "^v"    = "pageDown:";

      "~&lt;" = "moveToBeginningOfDocument:";
      "~&gt;" = "moveToEndOfDocument:";

      "^/"    = "undo:";
      "~/"    = "complete:";

      "^g"    = "_cancelKey:";
      "^a"    = "moveToBeginningOfLine:";
      "^e"    = "moveToEndOfLine:";

      "~c"	  = "capitalizeWord:";
      "~u"	  = "uppercaseWord:";
      "~l"	  = "lowercaseWord:";
      "^t"	  = "transpose:";
      "~t"	  = "transposeWords:";
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
