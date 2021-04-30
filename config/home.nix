{ pkgs, config, ... }:

let home_directory = builtins.getEnv "HOME";
    tmp_directory  = "/tmp";
    ca-bundle_path = "${pkgs.cacert}/etc/ssl/certs/";
    ca-bundle_crt  = "${ca-bundle_path}/ca-bundle.crt";
    emacs-server   = "${tmp_directory}/johnw-emacs/server";

    lib = pkgs.lib;
    localconfig = import <localconfig>;

    vulcan_ethernet = "192.168.1.69";
    vulcan_wifi     = "192.168.1.90";

    athena_ethernet = "192.168.1.80";
    athena_wifi     = "192.168.1.68";

    hermes_ethernet = "192.168.1.108";
    hermes_wifi     = "192.168.1.67";

in {
  home = {
    # These are packages that should always be present in the user
    # environment, though perhaps not the machine environment.
    packages = pkgs.callPackage ./packages.nix {};

    sessionVariables = {
      ASPELL_CONF        = "conf ${config.xdg.configHome}/aspell/config;";
      B2_ACCOUNT_INFO    = "${config.xdg.configHome}/backblaze-b2/account_info";
      BORG_PASSCOMMAND   = "${pkgs.pass}/bin/pass show Passwords/borgbackup";
      CABAL_CONFIG       = "${config.xdg.configHome}/cabal/config";
      FONTCONFIG_FILE    = "${config.xdg.configHome}/fontconfig/fonts.conf";
      FONTCONFIG_PATH    = "${config.xdg.configHome}/fontconfig";
      GNUPGHOME          = "${config.xdg.configHome}/gnupg";
      GRAPHVIZ_DOT       = "${pkgs.graphviz}/bin/dot";
      LESSHISTFILE       = "${config.xdg.cacheHome}/less/history";
      LOCATE_PATH        = "${config.xdg.cacheHome}/locate/home.db:${config.xdg.cacheHome}/locate/system.db";
      NIX_CONF           = "${home_directory}/src/nix";
      PARALLEL_HOME      = "${config.xdg.cacheHome}/parallel";
      PASSWORD_STORE_DIR = "${home_directory}/doc/.passwords";
      RECOLL_CONFDIR     = "${config.xdg.configHome}/recoll";
      SCREENRC           = "${config.xdg.configHome}/screen/config";
      SSH_AUTH_SOCK      = "${config.xdg.configHome}/gnupg/S.gpg-agent.ssh";
      STARDICT_DATA_DIR  = "${config.xdg.dataHome}/dictionary";
      TRAVIS_CONFIG_PATH = "${config.xdg.configHome}/travis";
      VAGRANT_HOME       = "${config.xdg.dataHome}/vagrant";
      WWW_HOME           = "${config.xdg.cacheHome}/w3m";
      EMACS_SERVER_FILE  = "${emacs-server}";
      EDITOR             = "${pkgs.emacs}/bin/emacsclient -s ${emacs-server}";
      EMAIL              = "${config.programs.git.userEmail}";
      JAVA_OPTS          = "-Xverify:none";
      VULCAN_ETHERNET    = vulcan_ethernet;
      VULCAN_WIFI        = vulcan_wifi;
      ATHENA_ETHERNET    = athena_ethernet;
      ATHENA_WIFI        = athena_wifi;
      HERMES_ETHERNET    = hermes_ethernet;
      HERMES_WIFI        = hermes_wifi;

      RCLONE_PASSWORD_COMMAND        = "${pkgs.pass}/bin/pass show Passwords/rclone-b2";
      RESTIC_PASSWORD_COMMAND        = "${pkgs.pass}/bin/pass show Passwords/restic";
      VAGRANT_DEFAULT_PROVIDER       = "vmware_desktop";
      VAGRANT_VMWARE_CLONE_DIRECTORY = "${home_directory}/Machines/vagrant";
      FILTER_BRANCH_SQUELCH_WARNING  = "1";
    };

    file = builtins.listToAttrs (
      map (path: {
             name = path;
             value = {
               source = builtins.toPath("${home_directory}/src/home/${path}");
             };
           })
          [ "Library/Scripts/Applications/Download links to PDF.scpt"
            "Library/Scripts/Applications/Media Pro" ]) // {

        ".ledgerrc".text = ''
          --file ${home_directory}/doc/accounts/main.ledger
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
    certificatesFile = "${ca-bundle_crt}";

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
      msmtp.enable = true;
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
        key = "46C4BD1A7AC14BA2";
        signByDefault = false;
        encryptByDefault = false;
      };
    };
  };

  programs = {
    direnv.enable = true;
    jq.enable = true;
    htop.enable = true;
    info.enable = true;
    man.enable = true;
    tmux.enable = true;
    vim.enable = true;

    msmtp = {
      enable = true;
      extraConfig =''
        logfile ${config.xdg.dataHome}/msmtp/msmtp.log
      '';
    };

    home-manager = {
      enable = true;
      path = "${home_directory}/src/nix/home-manager";
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

    bash = {
      enable = true;
      bashrcExtra = lib.mkBefore ''
        source /etc/bashrc
      '';
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    zsh = rec {
      enable = true;

      dotDir = ".config/zsh";
      enableCompletion = false;
      enableAutosuggestions = true;

      history = {
        size = 50000;
        save = 500000;
        path = "${dotDir}/history";
        ignoreDups = true;
        share = true;
      };

      sessionVariables = {
        ALTERNATE_EDITOR  = "${pkgs.vim}/bin/vi";
        LC_CTYPE          = "en_US.UTF-8";
        LEDGER_COLOR      = "true";
        LESS              = "-FRSXM";
        LESSCHARSET       = "utf-8";
        PAGER             = "less";
        PROMPT            = "%m %~ $ ";
        PROMPT_DIRTRIM    = "2";
        RPROMPT           = "";
        TERM              = "xterm-256color";
        TINC_USE_NIX      = "yes";
        WORDCHARS         = "";
      };

      shellAliases = {
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
        nstat  = "${pkgs.darwin.network_cmds}/bin/netstat -nr -f inet"
               + " | ${pkgs.gnugrep}/bin/egrep -v \"(lo0|vmnet|169\\.254|255\\.255)\""
               + " | ${pkgs.coreutils}/bin/tail -n +5";

        # Use whichever cabal is on the PATH.
        cn     = "cabal new-configure --enable-tests --enable-benchmarks";
        cnp    = "cabal new-configure --enable-tests --enable-benchmarks " +
                 "--enable-profiling --ghc-options=-fprof-auto";
        cb     = "cabal new-build";

        # Use whichever terraform is on the PATH.
        deploy = ''${pkgs.nix}/bin/nix-shell --pure --command '' +
          ''"terraform init; '' +
          ''export GITHUB_TOKEN=$(${pkgs.pass}/bin/pass show api.github.com | head -1); '' +
          ''terraform apply"'';

        rehash = "hash -r";
      };

      profileExtra = ''
        export GPG_TTY=$(tty)
        if ! pgrep -x "gpg-agent" > /dev/null; then
            ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
        fi

        . ${pkgs.z}/share/z.sh

        defaults write org.hammerspoon.Hammerspoon MJConfigFile \
            "${config.xdg.configHome}/hammerspoon/init.lua"

        for i in rdm msmtp privoxy tor; do
            dir=${config.xdg.dataHome}/$i
            if [[ ! -d $dir ]]; then mkdir -p $dir; fi
        done

        setopt extended_glob
      '';

      initExtra = lib.mkBefore ''
        export PATH=$(echo "$PATH" | sed 's/\/usr\/local\/bin:\/usr\/bin:\/bin:\/usr\/sbin:\/sbin://')
        export PATH=${home_directory}/doc/accounts/bin:$PATH
        export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
        export PATH=$(echo "$PATH" | sed 's/\/Applications\/VMware Fusion\.app\/Contents\/Public://')

        export SSH_AUTH_SOCK=$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)

        function upload() {
            ${pkgs.lftp}/bin/lftp -u johnw@newartisans.com,$(${pkgs.pass}/bin/pass show ftp.fastmail.com | head -1) \
                ftp://johnw@newartisans.com@ftp.fastmail.com                 \
                -e "set ssl:ca-file \"${ca-bundle_crt}\"; cd /johnw.newartisans.com/files/pub ; put \"$1\" ; quit"

            file=$(basename "$1" | sed -e 's/ /%20/g')
            echo "http://ftp.newartisans.com/pub/$file" | pbcopy
        }

        if [[ $TERM == dumb || $TERM == emacs || ! -o interactive ]]; then
            unsetopt zle
            unset zle_bracketed_paste
            export PS1='%m %~ $ '
        else
           . ${config.xdg.configHome}/zsh/plugins/iterm2_shell_integration
           . ${config.xdg.configHome}/zsh/plugins/iterm2_tmux_integration
        fi
      '';

      plugins = [
        {
          name = "iterm2_shell_integration";
          src = pkgs.fetchurl {
            url = https://iterm2.com/shell_integration/zsh;
            sha256 = "1qm7khz19dhwgz4aln3yy5hnpdh6pc8nzxp66m1za7iifq9wrvil";
            # date = 2020-01-07T15:59:09-0800;
          };
        }
        {
          name = "iterm2_tmux_integration";
          src = pkgs.fetchurl {
            url = https://gist.githubusercontent.com/antifuchs/c8eca4bcb9d09a7bbbcd/raw/3ebfecdad7eece7c537a3cd4fa0510f25d02611b/iterm2_zsh_init.zsh;
            sha256 = "1v1b6yz0lihxbbg26nvz85c1hngapiv7zmk4mdl5jp0fsj6c9s8c";
            # date = 2020-01-07T15:59:13-0800;
          };
        }
      ];
    };

    git = {
      enable = true;
      package = pkgs.gitFull;

      userName  = "John Wiegley";
      userEmail = "johnw@newartisans.com";

      signing = {
        key = "C144D8F4F19FE630";
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
          editor            = "${pkgs.emacs}/bin/emacsclient -s ${emacs-server}";
          trustctime        = false;
          fsyncobjectfiles  = true;
          # pager             = "${pkgs.less}/bin/less --tabs=4 -RFX";
          pager             = "${pkgs.gitAndTools.delta}/bin/delta --plus-color=\"#012800\" --minus-color=\"#340001\" --theme='ansi-dark'";
          logAllRefUpdates  = true;
          precomposeunicode = false;
          whitespace        = "trailing-space,space-before-tab";
        };

        interactive.diffFilter = "${pkgs.gitAndTools.delta}/bin/delta --color-only";
        branch.autosetupmerge = true;
        commit.gpgsign        = true;
        github.user           = "jwiegley";
        credential.helper     = "${pkgs.pass-git-helper}/bin/pass-git-helper";
        ghi.token             = "!${pkgs.pass}/bin/pass show api.github.com | head -1";
        hub.protocol          = "${pkgs.openssh}/bin/ssh";
        mergetool.keepBackup  = true;
        pull.rebase           = true;
        rebase.autosquash     = true;
        rerere.enabled        = true;

        "merge \"ours\"".driver   = true;
        "magithub \"ci\"".enabled = false;

        http = {
          sslCAinfo = "${ca-bundle_crt}";
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
        "*.aux"
        "*.dylib"
        "*.elc"
        "*.glob"
        "*.la"
        "*.o"
        "*.so"
        "*.v.d"
        "*.vo"
        "*~"
        ".clean"
        ".direnv"
        ".envrc"
        ".envrc.cache"
        ".envrc.override"
        ".ghc.environment.x86_64-darwin-*"
        ".makefile"
        "TAGS"
        "cabal.project.local"
        "dist-newstyle"
        "result"
        "result-*"
        "tags"
      ];
    };

    ssh = {
      enable = true;

      controlMaster  = "auto";
      controlPath    = "${tmp_directory}/ssh-%u-%r@%h:%p";
      controlPersist = "1800";

      forwardAgent = true;
      serverAliveInterval = 60;

      hashKnownHosts = true;
      userKnownHostsFile = "${config.xdg.configHome}/ssh/known_hosts";

      extraConfig = ''
        Host default
          HostName 127.0.0.1
          User vagrant
          Port 2222
          UserKnownHostsFile /dev/null
          StrictHostKeyChecking no
          PasswordAuthentication no
          IdentityFile /Users/johnw/dfinity/master/.vagrant/machines/default/vmware_desktop/private_key
          IdentitiesOnly yes
          LogLevel FATAL
      '';

      matchBlocks =
        let onHost = proxy: hostname: { inherit hostname; } //
          (if "${localconfig.hostname}" == proxy then {} else {
             proxyJump = proxy;
           }); in
        (if    "${localconfig.hostname}" == "vulcan"
            || "${localconfig.hostname}" == "hermes"
            || "${localconfig.hostname}" == "athena"
            then {
           vulcan.hostname = vulcan_ethernet;
         } else {
           vulcan = {
             hostname = "2600:1700:cf00:db0:f1b3:ab80:3419:685d";
             port = 2201;
             extraOptions = {
               "LocalForward" = "5999 127.0.0.1:5900";
             };
           };
         }) // rec {

        hermes  = onHost "vulcan" hermes_ethernet;
        athena  = onHost "vulcan" athena_ethernet;
        tank    = athena;

        # router  = { hostname = "192.168.1.98"; user = "root"; };

        nixos   = onHost "vulcan" "192.168.118.128";
        dfinity = onHost "vulcan" "192.168.118.136";
        macos   = onHost "vulcan" "172.16.20.139";
        ubuntu  = onHost "vulcan" "172.16.20.141";

        elpa        = { hostname = "elpa.gnu.org"; user = "root"; };
        haskell_org = { host = "*haskell.org";     user = "root"; };

        savannah.hostname  = "git.sv.gnu.org";
        fencepost.hostname = "fencepost.gnu.org";
        launchpad.hostname = "bazaar.launchpad.net";
        mail.hostname      = "mail.haskell.org";

        keychain = {
          host = "*";
          extraOptions = {
            "UseKeychain"    = "yes";
            "AddKeysToAgent" = "yes";
            "IgnoreUnknown"  = "UseKeychain";
          };
        };

        id_local = {
          host = lib.concatStringsSep " " [
            "hermes" "athena" "home" "mac1*" "macos*" "nixos*" "mohajer"
            "dfinity" "smokeping" "tank" "titan" "ubuntu*" "vulcan"
          ];
          identityFile = "${config.xdg.configHome}/ssh/id_local";
          identitiesOnly = true;
          user = "johnw";
        };

        nix-docker = {
          hostname = "127.0.0.1";
          proxyJump = "athena";
          user = "root";
          port = 3022;
          identityFile = "${config.xdg.configHome}/ssh/nix-docker_rsa";
          identitiesOnly = true;
        };

        # DFINITY Machines

        id_dfinity = {
          host = lib.concatStringsSep " " [
            "hydra"
            "pa-1" "pa-darwin-1" "pa-darwin-2"
            "zrh-1" "zrh-2" "zrh-3" "zrh-darwin-1"
          ];
          identityFile = [ "${config.xdg.configHome}/ssh/id_dfinity"
                           "${config.xdg.configHome}/ssh/id_dfinity_old" ];
          identitiesOnly = true;
        };

        # DFINITY Machines on AWS

        hydra = {
          hostname = "hydra.dfinity.systems";
          user = "ec2-user";
        };

        # DFINITY Machines in Palo Alto

        pa-1 = {
          hostname = "pa-linux-1.dfinity.systems";
          user = "johnw";
        };

        # This requires a VPN connection to the DFINITY network.

        pa-darwin-1 = {
          hostname = "pa-darwin-1.dfinity.systems";
          user = "dfinity";
        };

        pa-darwin-2 = {
          hostname = "pa-darwin-2.dfinity.systems";
          user = "dfnmain";
        };

        # DFINITY Machines in Zurich

        zrh-1 = {
          hostname = "zrh-linux-1.dfinity.systems";
          user = "johnw";
        };

        zrh-2 = {
          hostname = "zrh-linux-2.dfinity.systems";
          user = "johnw";
        };

        zrh-3 = {
          hostname = "zrh-linux-3.dfinity.systems";
          user = "johnw";
        };

        zrh-darwin-1 = {
          hostname = "10.129.0.99";
          user = "dfinity";
        };

        demo-1.hostname = "10.11.18.1";
        demo-2.hostname = "10.11.18.2";
        demo-3.hostname = "10.11.18.3";
        demo-4.hostname = "10.11.18.4";

        demo-options = {
          host = lib.concatStringsSep " " [
            "demo-*"
          ];
          # proxyJump = "zrh-3";
          user = "root";
          extraOptions = {
            "PreferredAuthentications" = "password";
            "PubkeyAuthentication"     = "no";
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
      application/pdf = ${pkgs.emacs}/bin/emacsclient -n -s ${emacs-server} --eval '(org-pdfview-open "%f::%p")'
    '';

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
  };

  targets.darwin.keybindings = {
    "~f"    = "moveWordForward:";
    "~b"    = "moveWordBackward:";

    "~d"    = "deleteWordForward:";
    "~^h"   = "deleteWordBackward:";
    "~\010" = "deleteWordBackward:";    /* Option-backspace */
    "~\177" = "deleteWordBackward:";    /* Option-delete */

    "~v"    = "pageUp:";
    "^v"    = "pageDown:";

    "~<"    = "moveToBeginningOfDocument:";
    "~>"    = "moveToEndOfDocument:";

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
}
