{ pkgs, lib, config, hostname, inputs, ... }:

let am_traveling    = false;

    home            = builtins.getEnv "HOME";
    tmpdir          = "/tmp";

    userName        = "John Wiegley";
    userEmail       = "johnw@newartisans.com";

    ca-bundle_path  = "${pkgs.cacert}/etc/ssl/certs/";
    ca-bundle_crt   = "${ca-bundle_path}/ca-bundle.crt";
    emacs-server    = "${tmpdir}/johnw-emacs/server";
    emacsclient     = "${pkgs.emacs}/bin/emacsclient -s ${emacs-server}";

    vulcan_ethernet = if hostname == "hermes"
                      then "192.168.2.1"
                      else "192.168.50.51";
    vulcan_wifi     = "192.168.50.172";

    hermes_ethernet = if hostname == "vulcan"
                      then "192.168.2.2"
                      else "192.168.50.212";
    hermes_wifi     = "192.168.50.102";

    athena_ethernet = "192.168.50.235";

    external_ip     = "newartisans.hopto.org";

    master_key      = "4710CF98AF9B327BB80F60E146C4BD1A7AC14BA2";
    signing_key     = "E0F96E618528E465";

in {
  home = {
    stateVersion = "23.11";
    enableNixpkgsReleaseCheck = false;

    # These are packages that should always be present in the user
    # environment, though perhaps not the machine environment.
    packages = import ./packages.nix hostname inputs pkgs;

    sessionVariables = {
      ASPELL_CONF        = "conf ${config.xdg.configHome}/aspell/config;";
      B2_ACCOUNT_INFO    = "${config.xdg.configHome}/backblaze-b2/account_info";
      CABAL_CONFIG       = "${config.xdg.configHome}/cabal/config";
      EDITOR             = "${emacsclient}";
      EMACS_SERVER_FILE  = "${emacs-server}";
      EMAIL              = "${userEmail}";
      FONTCONFIG_FILE    = "${config.xdg.configHome}/fontconfig/fonts.conf";
      FONTCONFIG_PATH    = "${config.xdg.configHome}/fontconfig";
      GNUPGHOME          = "${config.xdg.configHome}/gnupg";
      GRAPHVIZ_DOT       = "${pkgs.graphviz}/bin/dot";
      GTAGSCONF          = "${pkgs.global}/share/gtags/gtags.conf";
      GTAGSLABEL         = "pygments";
      HOSTNAME           = hostname;
      JAVA_OPTS          = "-Xverify:none";
      LESSHISTFILE       = "${config.xdg.cacheHome}/less/history";
      NIX_CONF           = "${home}/src/nix";
      OLLAMA_MODELS      = if hostname == "vulcan"
                           then "/Volumes/ext/Models"
                           else "${config.xdg.dataHome}/ollama/models";
      PARALLEL_HOME      = "${config.xdg.cacheHome}/parallel";
      SCREENRC           = "${config.xdg.configHome}/screen/config";
      SSH_AUTH_SOCK      = "${config.xdg.configHome}/gnupg/S.gpg-agent.ssh";
      STARDICT_DATA_DIR  = "${config.xdg.dataHome}/dictionary";
      TRAVIS_CONFIG_PATH = "${config.xdg.configHome}/travis";
      VAGRANT_HOME       = "${config.xdg.dataHome}/vagrant";
      WWW_HOME           = "${config.xdg.cacheHome}/w3m";
      TZ                 = "PST8PDT";

      VULCAN_ETHERNET    = vulcan_ethernet;
      VULCAN_WIFI        = vulcan_wifi;
      HERMES_ETHERNET    = hermes_ethernet;
      HERMES_WIFI        = hermes_wifi;
      ATHENA_ETHERNET    = athena_ethernet;

      RESTIC_PASSWORD_COMMAND        = "${pkgs.pass}/bin/pass show Passwords/restic";
      VAGRANT_DEFAULT_PROVIDER       = "vmware_desktop";
      VAGRANT_VMWARE_CLONE_DIRECTORY = "${home}/Machines/vagrant";
      FILTER_BRANCH_SQUELCH_WARNING  = "1";

      MANPATH = lib.concatStringsSep ":" [
        "${home}/.nix-profile/share/man"
        "/run/current-system/sw/share/man"
        "/usr/local/share/man"
        "/usr/share/man"
      ];
    };

    sessionPath = [
      "/usr/local/bin"
      "/usr/local/zfs/bin"
      "/opt/homebrew/bin"
      "${home}/kadena/bin"
    ];

    file =
      let mkLink = config.lib.file.mkOutOfStoreSymlink; in
      {
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

        ".cups".source        = mkLink "${config.xdg.configHome}/cups";
        ".dbvis".source       = mkLink "${config.xdg.configHome}/dbvis";
        ".gist".source        = mkLink "${config.xdg.configHome}/gist/api_key";
        ".gnupg".source       = mkLink "${config.xdg.configHome}/gnupg";
        ".jupyter".source     = mkLink "${config.xdg.configHome}/jupyter";
        ".sage".source        = mkLink "${config.xdg.configHome}/sage";
        ".jq".source          = mkLink "${config.xdg.configHome}/jq/config";
        ".parallel".source    = mkLink "${config.xdg.configHome}/parallel";

        ".ollama".source      = mkLink "${config.xdg.configHome}/ollama";
        "${config.xdg.configHome}/ollama/models".source = mkLink "${config.xdg.dataHome}/ollama/models";

        ".cargo".source       = mkLink "${config.xdg.dataHome}/cargo";
        ".docker".source      = mkLink "${config.xdg.dataHome}/docker";
        ".w3m".source         = mkLink "${config.xdg.dataHome}/w3m";

        ".thinkorswim".source = mkLink "${config.xdg.cacheHome}/thinkorswim";

        ".emacs.d".source     = mkLink "${home}/src/dot-emacs";
        "dl".source           = mkLink "${home}/Downloads";
        "iCloud".source       = mkLink "${home}/Library/Mobile Documents/com~apple~CloudDocs";
      }
      // lib.optionalAttrs (hostname == "vulcan") {
        "Audio".source           = mkLink "/Volumes/ext/Audio";
        "Photos".source          = mkLink "/Volumes/ext/Photos";
        "Video".source           = mkLink "/Volumes/ext/Video";

        "_Archived Items".source = mkLink "/Volumes/ext/_Archived Items";

        "${config.xdg.dataHome}/ollama/models".source = mkLink "/Volumes/ext/Models";
      }
      // lib.optionalAttrs (hostname == "hermes") {
        "Audio".source  = mkLink "${home}/Library/CloudStorage/ShellFish/Vulcan/Audio";
        "Photos".source = mkLink "${home}/Library/CloudStorage/ShellFish/Vulcan/Photos";
        "Video".source  = mkLink "${home}/Library/CloudStorage/ShellFish/Athena/Video";
      }
      // lib.optionalAttrs (hostname == "athena") {
        "Audio".source  = mkLink "/Volumes/tank/Audio";
        "Photos".source = mkLink "/Volumes/tank/Photos";
        "Video".source  = mkLink "/Volumes/tank/Video";
        "Media".source  = mkLink "/Volumes/tank/Media";
      }
      // lib.optionalAttrs (hostname != "athena") {
        "org".source    = mkLink "${home}/doc/org";

        "Mobile".source = mkLink "${home}/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org";
        "Drafts".source = mkLink "${home}/Library/Mobile Documents/iCloud~com~agiletortoise~Drafts5/Documents";
        "Inbox".source  = mkLink "${home}/Library/Application Support/DEVONthink 3/Inbox";

        "Media".source  = mkLink "${home}/Library/CloudStorage/ShellFish/Athena/Media";
        "Athena".source = mkLink "${home}/Library/CloudStorage/ShellFish/Athena";
      };
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

    tmux = {
      enable = true;
      extraConfig = "set-option -g allow-passthrough";
    };

    home-manager = {
      enable = true;
      path = "${home}/src/nix/home-manager";
    };

    # TODO re-enable on Darwin when
    # https://github.com/NixOS/nixpkgs/pull/236258#issuecomment-1583450593 is fixed
    # browserpass = {
    #   enable = true;
    #   browsers = [ "firefox" ];
    # };

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
      dotDir = ".config/zsh";

      enable = true;
      enableCompletion = false;

      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      history = {
        size       = 50000;
        save       = 500000;
        path       = "${config.xdg.configHome}/zsh/history";
        ignoreDups = true;
        share      = true;
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
        g      = "${pkgs.gitAndTools.hub}/bin/hub";
        git    = "${pkgs.gitAndTools.hub}/bin/hub";
        # ga     = "${pkgs.gitAndTools.git-annex}/bin/git-annex";
        good   = "${pkgs.git}/bin/git bisect good";
        bad    = "${pkgs.git}/bin/git bisect bad";
        # ls     = "${pkgs.coreutils}/bin/ls --color=auto";
        ls     = "${pkgs.eza}/bin/eza";
        find   = "${pkgs.fd}/bin/fd";
        par    = "${pkgs.parallel}/bin/parallel";
        rm     = "${pkgs.my-scripts}/bin/trash";
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
        # export GPG_TTY=$(tty)
        # if ! pgrep -x "gpg-agent" > /dev/null; then
        #     ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
        # fi

        . ${pkgs.z}/share/z.sh

        setopt extended_glob
      '';

      initExtra = ''
        # Make sure that fzf does not override the meaning of ^T
        bindkey '^T' transpose-chars

        if [[ $TERM == dumb || $TERM == emacs || ! -o interactive ]]; then
            unsetopt zle
            unset zle_bracketed_paste
            export PROMPT='$ '
            export RPROMPT=""
            export PS1='$ '
        else
           export TERM="xterm-256color"

           . ${config.xdg.configHome}/zsh/plugins/iterm2_shell_integration
           . ${config.xdg.configHome}/zsh/plugins/iterm2_tmux_integration
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
            sha256 = "1xk6kx5kdn5wbqgx2f63vnafhkynlxnlshxrapkwkd9zf2531bqa";
            # date = 2024-05-23T13:52:02-0700;
          };
        }
        {
          name = "iterm2_tmux_integration";
          src = pkgs.fetchurl {
            url = https://gist.githubusercontent.com/antifuchs/c8eca4bcb9d09a7bbbcd/raw/3ebfecdad7eece7c537a3cd4fa0510f25d02611b/iterm2_zsh_init.zsh;
            sha256 = "1v1b6yz0lihxbbg26nvz85c1hngapiv7zmk4mdl5jp0fsj6c9s8c";
            # date = 2024-05-23T13:52:04-0700;
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
      package = pkgs.gitFull;

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
        rerere.enabled         = true;
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

        "url \"git://github.com/ghc/packages-\"".insteadOf
          = "git://github.com/ghc/packages/";
        "url \"http://github.com/ghc/packages-\"".insteadOf
          = "http://github.com/ghc/packages/";
        "url \"https://github.com/ghc/packages-\"".insteadOf
          = "https://github.com/ghc/packages/";
        "url \"ssh://git@github.com/ghc/packages-\"".insteadOf
          = "ssh://git@github.com/ghc/packages/";
        "url \"git@github.com:/ghc/packages-\"".insteadOf
          = "git@github.com:/ghc/packages/";
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

      controlMaster  = "auto";
      controlPath    = "${tmpdir}/ssh-%u-%r@%h:%p";
      controlPersist = "1800";

      forwardAgent = true;
      serverAliveInterval = 60;

      hashKnownHosts = true;
      userKnownHostsFile = "${config.xdg.configHome}/ssh/known_hosts";

      matchBlocks =
        let
          onHost = proxyJump: hostname: { inherit hostname; } //
            lib.optionalAttrs (hostname != proxyJump) {
              inherit proxyJump;
            };
          withLocal = attrs: attrs // {
            identityFile = "${home}/${hostname}/id_${hostname}";
          };
        in rec {

        # This is vulcan, as accessible from remote
        home = {
          hostname = external_ip;
          port = 2201;
        };

        # This is athena, as accessible from remote
        build = {
          hostname = external_ip;
          port = 2202;
        };

        vulcan = withLocal (if hostname == "hermes" && am_traveling
                            then home
                            else { hostname = vulcan_ethernet; });
        deimos = withLocal (onHost "vulcan" "192.168.221.128");
        simon  = withLocal (onHost "vulcan" "172.16.194.158");

        athena = withLocal (if hostname == "hermes" && am_traveling
                            then build
                            else { hostname = athena_ethernet; });
        phobos = withLocal (onHost "athena" "192.168.50.111");

        hermes = withLocal (if hostname == "athena"
                            then { hostname = hermes_wifi; }
                            else { hostname = hermes_ethernet; });
        neso   = withLocal (onHost "hermes" "192.168.100.130");

        mohajer = {
          hostname = "192.168.50.120";
          user = "nasimwiegley";
        };

        router = {
          hostname = "192.168.50.1";
          user = "router";
          port = 2203;
        };

        elpa = { hostname = "elpa.gnu.org"; user = "root"; };

        mail.hostname      = "mail.haskell.org";
        savannah.hostname  = "git.sv.gnu.org";
        fencepost.hostname = "fencepost.gnu.org";

        savannah_gnu_org = {
          host = lib.concatStringsSep " " [
            "git.savannah.gnu.org"
            "git.sv.gnu.org"
            "git.savannah.nongnu.org"
            "git.sv.nongnu.org"
          ];
          identityFile = "${config.xdg.configHome}/ssh/id_emacs";
        };

        haskell_org = { host = "*haskell.org"; user = "root"; };

        # Kadena
        chainweb_com = {
          host = "*.chainweb.com";
          user = "chainweb";
          identityFile = "${config.xdg.configHome}/ssh/id_kadena";
          extraOptions = {
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

  xdg = {
    enable = true;

    configFile = {
      "gnupg/gpg-agent.conf".text = ''
        enable-ssh-support
        default-cache-ttl 86400
        max-cache-ttl 86400
        pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
      '';

      "aspell/config".text = ''
        local-data-dir ${pkgs.aspell}/lib/aspell
        data-dir ${pkgs.aspellDicts.en}/lib/aspell
        personal ${config.xdg.configHome}/aspell/en_US.personal
        repl ${config.xdg.configHome}/aspell/en_US.repl
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

      "~c"	  = "capitalizeWord:"; /* M-c */
      "~u"	  = "uppercaseWord:";	 /* M-u */
      "~l"	  = "lowercaseWord:";	 /* M-l */
      "^t"	  = "transpose:";      /* C-t */
      "~t"	  = "transposeWords:"; /* M-t */
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
