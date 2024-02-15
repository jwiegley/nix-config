{ pkgs, lib, config, ... }:

let home            = builtins.getEnv "HOME";
    tmpdir          = "/tmp";
    localconfig     = import <localconfig>;

    userName        = "John Wiegley";
    userEmail       = "johnw@newartisans.com";

    ca-bundle_path  = "${pkgs.cacert}/etc/ssl/certs/";
    ca-bundle_crt   = "${ca-bundle_path}/ca-bundle.crt";
    emacs-server    = "${tmpdir}/johnw-emacs/server";
    emacsclient     = "${pkgs.emacs}/bin/emacsclient -s ${emacs-server}";

    vulcan_ethernet = if localconfig.hostname == "hermes"
                      then "192.168.233.1"
                      else "192.168.50.51";
    vulcan_wifi     = "192.168.50.172";

    hermes_ethernet = if localconfig.hostname == "vulcan"
                      then "192.168.233.5"
                      else "192.168.50.212";
    hermes_wifi     = "192.168.50.102";

    athena_ethernet = "192.168.50.235";
    athena_wifi     = "192.168.50.3";

    external_ip     = "newartisans.hopto.org";

    master_key      = "4710CF98AF9B327BB80F60E146C4BD1A7AC14BA2";
    signing_key     = "E0F96E618528E465";

in {
  home = {
    stateVersion = "18.09";

    # These are packages that should always be present in the user
    # environment, though perhaps not the machine environment.
    packages = import ./packages.nix pkgs;

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
      WWW_HOME           = "${config.xdg.cacheHome}/w3m";
      TZ                 = "PST8PDT";

      VULCAN_ETHERNET    = vulcan_ethernet;
      VULCAN_WIFI        = vulcan_wifi;
      HERMES_ETHERNET    = hermes_ethernet;
      HERMES_WIFI        = hermes_wifi;
      ATHENA_ETHERNET    = athena_ethernet;
      ATHENA_WIFI        = athena_wifi;

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
      "/usr/local/bin"
      "/usr/local/zfs/bin"
      "${home}/.ghcup/bin"
      "${home}/.rustup/toolchains/stable-x86_64-apple-darwin/bin"
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
      ".emacs.d".source     = mkLink "${home}/src/dot-emacs";
      ".gist".source        = mkLink "${config.xdg.configHome}/gist/api_key";
      ".gnupg".source       = mkLink "${config.xdg.configHome}/gnupg";
      ".jq".source          = mkLink "${config.xdg.configHome}/jq/config";
      ".macbeth".source     = mkLink "${config.xdg.configHome}/macbeth";
      ".mbsyncrc".source    = mkLink "${config.xdg.configHome}/mbsync/config";
      ".parallel".source    = mkLink "${config.xdg.configHome}/parallel";
      ".recoll".source      = mkLink "${config.xdg.configHome}/recoll";
      ".slate".source       = mkLink "${config.xdg.configHome}/slate/config";
      ".zekr".source        = mkLink "${config.xdg.configHome}/zekr";

      ".cargo".source       = mkLink "${config.xdg.dataHome}/cargo";
      ".docker".source      = mkLink "${config.xdg.dataHome}/docker";
      ".rustup".source      = mkLink "${config.xdg.dataHome}/rustup";
      ".ghcup".source       = mkLink "${config.xdg.dataHome}/ghcup";
      ".mbsync".source      = mkLink "${config.xdg.dataHome}/mbsync";

      ".thinkorswim".source = mkLink "${config.xdg.cacheHome}/thinkorswim";
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
      msmtp = {
        enable = true;
        extraConfig = {
          logfile = "${config.xdg.dataHome}/msmtp/msmtp.log";
        };
      };
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
    msmtp.enable = true;
    tmux.enable = true;
    vim.enable = true;

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
        PROMPT           = "%B%m %~ %b\\$(git_super_status)%(!.#.$) ";
        PROMPT_DIRTRIM   = "2";
        RPROMPT          = "";
        TINC_USE_NIX     = "yes";
        WORDCHARS        = "";

        ZSH_THEME_GIT_PROMPT_CACHE = "yes";
        ZSH_THEME_GIT_PROMPT_CHANGED = "%{$fg[yellow]%}%{✚%G%}";
        ZSH_THEME_GIT_PROMPT_STASHED = "%{$fg_bold[yellow]%}%{⚑%G%}";
        ZSH_THEME_GIT_PROMPT_UPSTREAM_FRONT =" {%{$fg[yellow]%}";
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
            export PROMPT='$ '
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

           [ -f "$HOME/.ghcup/env" ] && source "$HOME/.ghcup/env"
           [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
        fi
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
            lib.optionalAttrs (localconfig.hostname != proxyJump) {
              inherit proxyJump;
            };
          withLocal = attrs: attrs //
            (if localconfig.hostname == "vulcan" then {
               identityFile = "${home}/vulcan/id_vulcan";
             }
             else if localconfig.hostname == "athena" then {
               identityFile = "${home}/athena/id_athena";
             }
             else if localconfig.hostname == "hermes" then {
               # always use the YubiKey when coming from a laptop
             }
             else {});
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

        vulcan = withLocal (if localconfig.hostname == "athena"
                            then { hostname = vulcan_wifi; }
                            else home);
        deimos = withLocal (onHost "vulcan" "172.16.194.157");
        simon  = withLocal (onHost "vulcan" "172.16.194.158");

        athena = withLocal (if localconfig.hostname == "vulcan"
                            then { hostname = athena_ethernet; }
                            else build);
        phobos = withLocal (onHost "athena" "192.168.50.111");

        hermes = withLocal ({ hostname = hermes_wifi; });
        neso   = withLocal (onHost "hermes" "192.168.100.130");

        mohajer = {
          hostname = "192.168.50.120";
          user = "nasimwiegley";
        };

        router = {
          hostname = "rt-ax88u-3f30.local";
          user = "router";
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

      "recoll/mimeview".text = ''
        xallexcepts- = application/pdf
        xallexcepts+ =
        [view]
        application/pdf = ${emacsclient} -n --eval '(org-pdfview-open "%f::%p")'
      '';
    } //
    (if pkgs.stdenv.targetPlatform.isx86_64 then {
       "fetchmail/config".text = ''
         poll imap.fastmail.com protocol IMAP port 993 auth password
           user '${userEmail}' there is johnw here
           ssl sslcertck sslcertfile "${ca-bundle_crt}"
           folder INBOX
           fetchall
           mda "${pkgs.dovecot}/libexec/dovecot/dovecot-lda -c /etc/dovecot/dovecot.conf -e"
       '';

       "fetchmail/config-lists".text = ''
         poll imap.fastmail.com protocol IMAP port 993 auth password
           user '${userEmail}' there is johnw here
           ssl sslcertck sslcertfile "${ca-bundle_crt}"
           folder 'Lists'
           fetchall
           mda "${pkgs.dovecot}/libexec/dovecot/dovecot-lda -c /etc/dovecot/dovecot.conf -e -m list.misc"
       '';

       "mbsync/config".text =
         let
           mailboxes = [
             ## These five are handled specially
             # "INBOX"
             # "mail.drafts"
             # "mail.sent"
             # "mail.archive"
             # "mail.spam"

             "mail.pending"
             "mail.spam.report"
             "mail.kadena"
             "mail.kadena.archive"
             "list.kadena"
             "list.kadena.amazon"
             "list.kadena.asana"
             "list.kadena.bill"
             "list.kadena.calendar"
             "list.kadena.expensify"
             "list.kadena.github"
             "list.kadena.google"
             "list.kadena.greenhouse"
             "list.kadena.immunefi"
             "list.kadena.justworks"
             "list.kadena.lattice"
             "list.kadena.notion"
             "list.kadena.slack"
             "list.finance"
             "list.types"
             "list.misc"
             "list.notifications"
             "list.ledger"
             # "list.haskell.announce"
             # "list.haskell.beginners"
             # "list.haskell.cabal"
             # "list.haskell.cafe"
             # "list.haskell.commercial"
             # "list.haskell.committee"
             # "list.haskell.community"
             # "list.haskell.ghc"
             "list.haskell.hackage-trustees"
             "list.haskell.infrastructure"
             # "list.haskell.libraries"
             # "list.haskell.prime"
             "list.haskell.admin"
             # "list.gnu"
             # "list.gnu.prog"
             # "list.gnu.prog.discuss"
             # "list.gnu.debbugs"
             "list.github"
             "list.emacs.sources"
             # "list.emacs.proofgeneral"
             # "list.emacs.manual"
             "list.emacs.org-mode"
             # "list.emacs.conf"
             # "list.emacs.help"
             # "list.emacs.bugs"
             "list.emacs.tangents"
             "list.emacs.devel"
             # "list.emacs.devel.owner"
             "list.emacs.announce"
             "list.coq"
             # "list.coq.ssreflect"
             "list.coq.devel"
             "list.bahai"
             # "list.bahai.ror"
             "list.bahai.ctg"
             "list.bahai.ctg.sunday"
             "list.bahai.study"
             # "list.bahai.anti-racism"
             "list.bahai.tarjuman"
           ];
           channelDecl = box: "Channel personal-${box}";
           mailboxRule = box: ''
             ${channelDecl box}
             Far :fastmail-remote:${builtins.replaceStrings ["."] ["/"] box}
             Near :dovecot-local:${box}
             Create Both
             Expunge Both
             Remove Both
             CopyArrivalDate yes
           '';
           allMailboxRules = builtins.concatStringsSep "\n" (builtins.map mailboxRule mailboxes);
           allChannelDecls = builtins.concatStringsSep "\n" (builtins.map channelDecl mailboxes);
         in ''
         IMAPAccount fastmail
         Host imap.fastmail.com
         User ${userEmail}
         PassCmd "pass imap.fastmail.com"
         SSLType IMAPS
         CertificateFile ${ca-bundle_crt}
         Port 993
         PipelineDepth 1

         IMAPStore fastmail-remote
         Account fastmail
         PathDelimiter /
         Trash Trash

         IMAPAccount dovecot
         SSLType None
         Host localhost
         Port 9143
         User johnw
         Pass pass
         AuthMechs PLAIN
         Tunnel "${pkgs.dovecot}/libexec/dovecot/imap -c /etc/dovecot/dovecot.conf"

         IMAPStore dovecot-local
         Account dovecot
         PathDelimiter /
         Trash mail.trash

         IMAPAccount gmail
         Host imap.gmail.com
         User jwiegley@gmail.com
         PassCmd "pass imap.gmail.com"
         SSLType IMAPS
         AuthMechs LOGIN
         CertificateFile ${ca-bundle_crt}
         Port 993
         PipelineDepth 1

         IMAPStore gmail-remote
         Account gmail
         PathDelimiter /
         Trash Trash

         Channel gmail-all-mail
         Far :gmail-remote:"[Gmail]/All Mail"
         Near :dovecot-local:mail.gmail
         Create Both
         Expunge Both
         Remove Both
         CopyArrivalDate yes

         IMAPAccount gmail-kadena
         Host imap.gmail.com
         User john@kadena.io
         PassCmd "pass kadena.imap.gmail.com"
         SSLType IMAPS
         AuthMechs LOGIN
         CertificateFile ${ca-bundle_crt}
         Port 993
         PipelineDepth 1

         IMAPStore gmail-kadena-remote
         Account gmail-kadena
         PathDelimiter /
         Trash Trash

         Channel gmail-kadena-all-mail
         Far :gmail-kadena-remote:"[Gmail]/All Mail"
         Near :dovecot-local:mail.gmail.kadena
         Create Both
         Expunge Both
         Remove Both
         CopyArrivalDate yes

         IMAPAccount gmail-c2g
         Host imap.gmail.com
         User john.wiegley@coppertogold.org
         PassCmd "pass c2g.imap.gmail.com"
         SSLType IMAPS
         AuthMechs LOGIN
         CertificateFile ${ca-bundle_crt}
         Port 993
         PipelineDepth 1

         IMAPStore gmail-c2g-remote
         Account gmail-c2g
         PathDelimiter /
         Trash Trash

         Channel gmail-c2g-all-mail
         Far :gmail-c2g-remote:"[Gmail]/All Mail"
         Near :dovecot-local:mail.gmail.c2g
         Create Both
         Expunge Both
         Remove Both
         CopyArrivalDate yes

         Channel personal-inbox
         Far :fastmail-remote:
         Near :dovecot-local:
         Patterns "INBOX"
         Create Both
         Expunge Both
         Remove Both
         CopyArrivalDate yes

         Channel personal-drafts
         Far :fastmail-remote:Drafts
         Near :dovecot-local:Drafts
         Create Both
         Expunge Both
         Remove Both
         CopyArrivalDate yes

         Channel personal-sent
         Far :fastmail-remote:Sent
         Near :dovecot-local:mail.sent
         Create Both
         Expunge Both
         Remove Both
         CopyArrivalDate yes

         Channel personal-archive
         Far :fastmail-remote:Archive
         Near :dovecot-local:mail.archive
         Create Both
         Expunge Both
         Remove Far
         CopyArrivalDate yes

         Channel personal-spam
         Far :fastmail-remote:Spam
         Near :dovecot-local:mail.spam
         Create Both
         Expunge Both
         Remove Both
         CopyArrivalDate yes

         ${allMailboxRules}

         Group personal
         Channel personal-inbox
         Channel personal-drafts
         Channel personal-sent
         Channel personal-archive
         channel personal-spam
         ${allChannelDecls}
         # Channel gmail-all-mail
         # Channel gmail-kadena-all-mail
         # Channel gmail-c2g-all-mail
       '';
     } else {});
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
