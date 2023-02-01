{ pkgs, lib, config, ... }:

let home            = builtins.getEnv "HOME";
    tmpdir          = "/tmp";
    localconfig     = import <localconfig>;

    ca-bundle_path  = "${pkgs.cacert}/etc/ssl/certs/";
    ca-bundle_crt   = "${ca-bundle_path}/ca-bundle.crt";
    emacs-server    = "${tmpdir}/johnw-emacs/server";
    emacsclient     = "${pkgs.emacs}/bin/emacsclient -s ${emacs-server}";

    vulcan_ethernet = "192.168.1.69";
    vulcan_wifi     = "192.168.1.90";

    athena_ethernet = "192.168.1.157";
    athena_wifi     = "192.168.1.91";

    hermes_ethernet = "192.168.1.108";
    hermes_wifi     = "192.168.1.67";

    master_key      = "4710CF98AF9B327BB80F60E146C4BD1A7AC14BA2";
    signing_key     = "E0F96E618528E465";

in {
  home = {
    stateVersion = "18.09";

    # These are packages that should always be present in the user
    # environment, though perhaps not the machine environment.
    packages = pkgs.callPackage ./packages.nix {};

    sessionVariables = {
      ASPELL_CONF        = "conf ${config.xdg.configHome}/aspell/config;";
      B2_ACCOUNT_INFO    = "${config.xdg.configHome}/backblaze-b2/account_info";
      CABAL_CONFIG       = "${config.xdg.configHome}/cabal/config";
      CHAINWEB_PGDATA    = "";
      EDITOR             = "${emacsclient}";
      EMACS_SERVER_FILE  = "${emacs-server}";
      EMAIL              = "${config.programs.git.userEmail}";
      FONTCONFIG_FILE    = "${config.xdg.configHome}/fontconfig/fonts.conf";
      FONTCONFIG_PATH    = "${config.xdg.configHome}/fontconfig";
      GNUPGHOME          = "${config.xdg.configHome}/gnupg";
      GRAPHVIZ_DOT       = "${pkgs.graphviz}/bin/dot";
      HERMES_ETHERNET    = hermes_ethernet;
      HERMES_WIFI        = hermes_wifi;
      HOSTNAME           = localconfig.hostname;
      JAVA_OPTS          = "-Xverify:none";
      LESSHISTFILE       = "${config.xdg.cacheHome}/less/history";
      NIX_CONF           = "${home}/src/nix";
      PARALLEL_HOME      = "${config.xdg.cacheHome}/parallel";
      RECOLL_CONFDIR     = "${config.xdg.configHome}/recoll";
      SCREENRC           = "${config.xdg.configHome}/screen/config";
      SSH_AUTH_SOCK      = "${config.xdg.configHome}/gnupg/S.gpg-agent.ssh";
      STARDICT_DATA_DIR  = "${config.xdg.dataHome}/dictionary";
      TRAVIS_CONFIG_PATH = "${config.xdg.configHome}/travis";
      VAGRANT_HOME       = "${config.xdg.dataHome}/vagrant";
      VULCAN_ETHERNET    = vulcan_ethernet;
      VULCAN_WIFI        = vulcan_wifi;
      ATHENA_ETHERNET    = athena_ethernet;
      ATHENA_WIFI        = athena_wifi;
      WWW_HOME           = "${config.xdg.cacheHome}/w3m";

      RCLONE_PASSWORD_COMMAND        = "${pkgs.pass}/bin/pass show Passwords/rclone-b2";
      RESTIC_PASSWORD_COMMAND        = "${pkgs.pass}/bin/pass show Passwords/restic";
      VAGRANT_DEFAULT_PROVIDER       = "vmware_desktop";
      VAGRANT_VMWARE_CLONE_DIRECTORY = "${home}/Machines/vagrant";
      FILTER_BRANCH_SQUELCH_WARNING  = "1";

      LOCATE_PATH = lib.concatStringsSep ":" [
        "${config.xdg.cacheHome}/locate/home.db"
        "${config.xdg.cacheHome}/locate/system.db"
      ];

      MANPATH = lib.concatStringsSep ":" [
        "${home}/.nix-profile/share/man"
        "/run/current-system/sw/share/man"
        "/usr/local/share/man"
        "/usr/share/man"
      ];
    };

    sessionPath = [
      "/usr/local/zfs/bin"
      "${home}/.ghcup/bin"
    ];

    file = builtins.listToAttrs (
      map (path: {
             name = path;
             value = {
               source = builtins.toPath("${home}/src/home/${path}");
             };
           })
          [ "Library/Scripts/Applications/Download links to PDF.scpt"
            "Library/Scripts/Applications/Media Pro" ]) // {

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
      };
  };

  accounts.email = {
    certificatesFile = ca-bundle_crt;

    accounts.fastmail = {
      realName = "John Wiegley";
      address = "johnw@newartisans.com";
      aliases = [
        "jwiegley@gmail.com"
        "johnw@gnu.org"
      ];
      userName = "johnw@newartisans.com";
      flavor = "plain";
      passwordCommand = "${pkgs.pass}/bin/pass show smtp.fastmail.com";
      primary = true;
      msmtp = {
        enable = true;
        extraConfig = {
          logfile = "${config.xdg.dataHome}/msmtp/msmtp.log";
        };
      };
      imap = {
        host = "imap.fastmail.com";
        port = 993;
        tls = {
          enable = true;
          useStartTls = false;
        };
      };
      smtp = {
        host = "smtp.fastmail.com";
        port = 587;
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
    direnv.enable = true;
    htop.enable = true;
    info.enable = true;
    jq.enable = true;
    man.enable = true;
    msmtp.enable = true;
    tmux.enable = true;
    vim.enable = true;

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
      enable = true;
      enableCompletion = false;
      enableAutosuggestions = true;
      dotDir = ".config/zsh";

      history = {
        size       = 50000;
        save       = 500000;
        path       = "${dotDir}/history";
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
        PROMPT           = "%m %~ $ ";
        PROMPT_DIRTRIM   = "2";
        RPROMPT          = "";
        TERM             = "xterm-256color";
        TINC_USE_NIX     = "yes";
        WORDCHARS        = "";
      };

      shellAliases = {
        vi     = "${pkgs.vim}/bin/vim";
        b      = "${pkgs.git}/bin/git b";
        l      = "${pkgs.git}/bin/git l";
        w      = "${pkgs.git}/bin/git w";
        g      = "${pkgs.gitAndTools.hub}/bin/hub";
        git    = "${pkgs.gitAndTools.hub}/bin/hub";
        ga     = "${pkgs.gitAndTools.git-annex}/bin/git-annex";
        good   = "${pkgs.git}/bin/git bisect good";
        bad    = "${pkgs.git}/bin/git bisect bad";
        ls     = "${pkgs.coreutils}/bin/ls --color=auto";
        nm     = "${pkgs.findutils}/bin/find . -name";
        par    = "${pkgs.parallel}/bin/parallel";
        rm     = "${pkgs.my-scripts}/bin/trash";
        rX     = "${pkgs.coreutils}/bin/chmod -R ugo+rX";
        scp    = "${pkgs.rsync}/bin/rsync -aP --inplace";
        wipe   = "${pkgs.srm}/bin/srm -vfr";
        switch = "${pkgs.nix-scripts}/bin/u ${localconfig.hostname} switch";
        proc   = "${pkgs.darwin.ps}/bin/ps axwwww | ${pkgs.gnugrep}/bin/grep -i";
        #nstat  = "${pkgs.darwin.network_cmds}/bin/netstat -nr -f inet"
        #       + " | ${pkgs.gnugrep}/bin/egrep -v \"(lo0|vmnet|169\\.254|255\\.255)\""
        #       + " | ${pkgs.coreutils}/bin/tail -n +5";

        # Use whichever cabal is on the PATH.
        cb     = "cabal build";
        cn     = "cabal configure --enable-tests --enable-benchmarks";
        cnp    = "cabal configure --enable-tests --enable-benchmarks " +
                 "--enable-profiling --ghc-options=-fprof-auto";

        rehash = "hash -r";
      };

      profileExtra = ''
        export GPG_TTY=$(tty)
        if ! pgrep -x "gpg-agent" > /dev/null; then
            ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
        fi

        . ${pkgs.z}/share/z.sh

        for i in rdm msmtp; do
            dir=${config.xdg.dataHome}/$i
            if [[ ! -d $dir ]]; then mkdir -p $dir; fi
        done

        setopt extended_glob
      '';

      initExtra = ''
        # Make sure that fzf does not override the meaning of ^T
        bindkey '^X^T' fzf-file-widget
        bindkey '^T' transpose-chars

        if [[ $TERM == dumb || $TERM == emacs || ! -o interactive ]]; then
            unsetopt zle
            unset zle_bracketed_paste
            export PS1='%m %~ $ '
        else
           . ${config.xdg.configHome}/zsh/plugins/iterm2_shell_integration
           . ${config.xdg.configHome}/zsh/plugins/iterm2_tmux_integration

           sudo /bin/launchctl limit maxfiles 524288 524288
           ulimit -n 65536

           autoload -Uz compinit
           compinit
           # eval "$(op completion zsh)"; compdef _op op
        fi

        function t() {
            opt="$1"
            shift 1
            exec cabal test --test-options="opt" "$@"
        }
      '';

      plugins = [
        {
          name = "iterm2_shell_integration";
          src = pkgs.fetchurl {
            url = https://iterm2.com/shell_integration/zsh;
            sha256 = "1xk6kx5kdn5wbqgx2f63vnafhkynlxnlshxrapkwkd9zf2531bqa";
            # date = 2022-12-28T10:15:23-0800;
          };
        }
        {
          name = "iterm2_tmux_integration";
          src = pkgs.fetchurl {
            url = https://gist.githubusercontent.com/antifuchs/c8eca4bcb9d09a7bbbcd/raw/3ebfecdad7eece7c537a3cd4fa0510f25d02611b/iterm2_zsh_init.zsh;
            sha256 = "1v1b6yz0lihxbbg26nvz85c1hngapiv7zmk4mdl5jp0fsj6c9s8c";
            # date = 2022-12-28T10:15:27-0800;
          };
        }
      ];
    };

    password-store = {
      enable = true;
      package = pkgs.pass.withExtensions (exts: [ exts.pass-otp exts.pass-genphrase ]);
      settings = {
        PASSWORD_STORE_DIR = "${home}/doc/.passwords";
      };
    };

    gpg = {
      enable = true;
      homedir = "${config.xdg.configHome}/gnupg";
      settings = {
        default-key = master_key;

        auto-key-locate = "keyserver";
        keyserver = "pgp.mit.edu";
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

      userName = "John Wiegley";
      userEmail = "johnw@newartisans.com";

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
        "dist-newstyle"
        "input-haskell-cabal.tar.gz"
        "input-haskell-hoogle.tar.gz"
        "input-haskell-platform.txt"
        "input-haskell-stackage-lts.txt"
        "input-haskell-stackage-nightly.txt"
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
        let onHost = proxyJump: hostname: { inherit hostname; } //
          lib.optionalAttrs (localconfig.hostname != proxyJump) {
            inherit proxyJump;
          }; in rec {

        # This is vulcan, as accessible from remote
        home = {
          hostname = "76.234.69.149";
          port = 2201;
          extraOptions = {
            LocalForward = "5999 127.0.0.1:5901";
          };
        };

        # This is athena, as accessible from remote
        build = {
          hostname = "76.234.69.149";
          port = 2202;
          extraOptions = {
            LocalForward = "5999 127.0.0.1:5902";
          };
        };

        vulcan.hostname = vulcan_ethernet;
        # vulcan = home;
        athena.hostname = athena_ethernet;
        # athena = build;
        hermes.hostname = hermes_ethernet;

        macos    = onHost "vulcan" "172.16.194.129";
        macos15  = onHost "vulcan" "172.16.194.136";
        ubuntu   = onHost "vulcan" "172.16.194.137";
        chainweb = onHost "vulcan" "192.168.1.152";

        mohajer = { hostname = "192.168.50.120"; user = "nasimwiegley"; };

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
          identitiesOnly = true;
        };

        id_local = {
          host = lib.concatStringsSep " " [
            "vulcan" "home" "hermes" "athena" "mohajer"
            "mac1*" "macos*" "nixos*" "smokeping" "tank" "ubuntu*"
          ];
          identityFile = "${config.xdg.configHome}/ssh/id_local";
          identitiesOnly = true;
          user = "johnw";
        };

        haskell_org = { host = "*haskell.org"; user = "root"; };

        # Kadena

        chainweb_com = {
          host = "*.chainweb.com";
          user = "chainweb";
          identityFile = "${config.xdg.configHome}/ssh/id_kadena";
          identitiesOnly = true;
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

    configFile."gnupg/gpg-agent.conf".text = ''
      enable-ssh-support
      default-cache-ttl 86400
      max-cache-ttl 86400
      pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
    '';

    configFile."aspell/config".text = ''
      local-data-dir ${pkgs.aspell}/lib/aspell
      data-dir ${pkgs.aspellDicts.en}/lib/aspell
      personal ${config.xdg.configHome}/aspell/en_US.personal
      repl ${config.xdg.configHome}/aspell/en_US.repl
    '';

    configFile."recoll/mimeview".text = ''
      xallexcepts- = application/pdf
      xallexcepts+ =
      [view]
      application/pdf = ${emacsclient} -n --eval '(org-pdfview-open "%f::%p")'
    '';
  } //
  (if pkgs.stdenv.targetPlatform.isx86_64 then {
    configFile."fetchmail/config".text = ''
      poll imap.fastmail.com protocol IMAP port 993 auth password
        user '${config.accounts.email.accounts.fastmail.address}' there is johnw here
        ssl sslcertck sslcertfile "${ca-bundle_crt}"
        folder INBOX
        fetchall
        mda "${pkgs.dovecot}/libexec/dovecot/dovecot-lda -c /etc/dovecot/dovecot.conf -e"
    '';

    configFile."fetchmail/config-lists".text = ''
      poll imap.fastmail.com protocol IMAP port 993 auth password
        user '${config.accounts.email.accounts.fastmail.address}' there is johnw here
        ssl sslcertck sslcertfile "${ca-bundle_crt}"
        folder 'Lists'
        fetchall
        mda "${pkgs.dovecot}/libexec/dovecot/dovecot-lda -c /etc/dovecot/dovecot.conf -e -m list.misc"
    '';
   } else {});

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
