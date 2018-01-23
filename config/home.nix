{ pkgs, ... }:

let home_directory = builtins.getEnv "HOME";
    lib = pkgs.stdenv.lib; in rec {

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowBroken = true;
    };

    overlays =
      let path = ../overlays; in with builtins;
      map (n: import (path + ("/" + n)))
          (filter (n: match ".*\\.nix" n != null ||
                      pathExists (path + ("/" + n + "/default.nix")))
                  (attrNames (readDir path)));
  };

  # services = {
  #   gpg-agent = {
  #     enable = true;
  #     defaultCacheTtl = 1800;
  #     enableSshSupport = true;
  #   };
  # };

  home = {
    # These are packages that should always be present in the user
    # environment, though perhaps not the machine environment.
    packages = with pkgs; [];

    sessionVariables = {
      ASPELL_CONF        = "conf ${xdg.configHome}/aspell/config;";
      B2_ACCOUNT_INFO    = "${xdg.configHome}/backblaze-b2/account_info";
      CABAL_CONFIG       = "${xdg.configHome}/cabal/config";
      GNUPGHOME          = "${xdg.configHome}/gnupg";
      LESSHISTFILE       = "${xdg.cacheHome}/less/history";
      PARALLEL_HOME      = "${xdg.cacheHome}/parallel";
      SCREENRC           = "${xdg.configHome}/screen/config";
      SSH_AUTH_SOCK      = "${xdg.configHome}/gnupg/S.gpg-agent.ssh";
      STARDICT_DATA_DIR  = "${xdg.dataHome}/dictionary";
      WWW_HOME           = "${xdg.cacheHome}/w3m";

      PASSWORD_STORE_DIR = "${home_directory}/Documents/.passwords";

      # OCAMLPATH          = "${pkgs.ocamlPackages.camlp5_transitional}"
      #                    + "/lib/ocaml/${pkgs.ocaml.version}/site-lib/camlp5";

      COQVER             = "87";
      EMACSVER           = "26";
      GHCVER             = "82";
      GHCPKGVER          = "822";

      ALTERNATE_EDITOR   = "${pkgs.vim}/bin/vi";
      COLUMNS            = "100";
      EDITOR             = "${pkgs.emacs}/bin/emacsclient -a vi";
      EMAIL              = "${programs.git.userEmail}";
      JAVA_OPTS          = "-Xverify:none";
      LC_CTYPE           = "en_US.UTF-8";
      LESS               = "-FRSXM";
      PROMPT_DIRTRIM     = "2";
      # PS1                = "\\D{%H:%M} \\h:\\W $ ";
      TINC_USE_NIX       = "yes";
      WORDCHARS          = "";
    };

    file = builtins.listToAttrs (
      map (path: {
             name = path;
             value = {
               source = builtins.toPath("${home_directory}/src/home/${path}");
             };
           })
          [ "Library/Keyboard Layouts/PersianDvorak.keylayout"
            "Library/Scripts/Applications/Download links to PDF.scpt"
            "Library/Scripts/Applications/Media Pro" ]) //
      { ".Deskzilla".source    = "${xdg.dataHome}/Deskzilla";
        ".dbvis".source        = "${xdg.configHome}/DbVisualizer";
        ".docker".source       = "${xdg.configHome}/docker";
        ".gist".source         = "${xdg.configHome}/gist/account_id";
        ".ledgerrc".text       = "--file /Volumes/Files/Accounts/ledger.dat\n";
        ".slate".source        = "${xdg.configHome}/slate/config";
        ".zekr".source         = "${xdg.dataHome}/zekr";
      };
  };

  programs.zsh = rec {
    enable = true;

    dotDir = ".config/zsh";
    enableCompletion = false;
    enableAutosuggestions = true;

    history = {
      size = 5000;
      save = 50000;
      path = "${dotDir}/history";
      ignoreDups = true;
      share = true;
    };

    sessionVariables = {
      POWERLEVEL9K_PROMPT_ON_NEWLINE = "true";
      POWERLEVEL9K_RPROMPT_ON_NEWLINE = "true";
    };

    shellAliases = {
      b = "${pkgs.git}/bin/git b";
      l = "${pkgs.git}/bin/git l";
      w = "${pkgs.git}/bin/git w";

      u = "${pkgs.gnumake}/bin/make -C ${home_directory}/src/nix -f Makefile";

      g   = "${pkgs.gitAndTools.hub}/bin/hub";
      git = "${pkgs.gitAndTools.hub}/bin/hub";
      ga  = "${pkgs.gitAndTools.git-annex}/bin/git-annex";

      ls    = "${pkgs.coreutils}/bin/ls --color=auto";
      nm    = "${pkgs.findutils}/bin/find . -name";
      par   = "${pkgs.parallel}/bin/parallel";
      rm    = "${home_directory}/src/scripts/trash";
      rX    = "${pkgs.coreutils}/bin/chmod -R ugo+rX";
      scp   = "${pkgs.rsync}/bin/rsync -aP --inplace";
      hide  = "chflags hidden";
      proc  = "ps axwwww | ${pkgs.gnugrep}/bin/grep -i";
      wipe  = "${pkgs.srm}/bin/srm -vfr";
      nstat = "netstat -nr -f inet"
            + " | ${pkgs.gnugrep}/bin/egrep -v \"(lo0|vmnet|169\\.254|255\\.255)\""
            + " | ${pkgs.coreutils}/bin/tail -n +5";

      hermes = "ssh -t hermes 'zsh -l'";
      vulcan = "ssh -t vulcan 'zsh -l'";
    };

    profileExtra = ''
      for file in ${xdg.configHome}/fetchmail/config \
                  ${xdg.configHome}/fetchmail/config-lists
      do
          cp -pL $file ''${file}.copy
          chmod 0600 ''${file}.copy
      done

      export GPG_TTY=$(tty)
      if ! pgrep -x "gpg-agent" > /dev/null; then
          ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
      fi

      function rmdir-r() {
          ${pkgs.findutils}/bin/find "$@" -depth -type d -empty \
              -exec ${pkgs.coreutils}/bin/rmdir {} \;
      }

      export POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(context dir rbenv vcs)
      export POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status root_indicator background_jobs history command_execution_time time)

      source ${pkgs.z}/share/z.sh
    '';

    initExtra = lib.mkBefore ''
      DOCKER_MACHINE=$(which docker-machine)
      if [[ -x "$DOCKER_MACHINE" ]]; then
          if $DOCKER_MACHINE status default > /dev/null 2>&1; then
              eval $($DOCKER_MACHINE env default) > /dev/null 2>&1
          fi
      fi

      export SSH_AUTH_SOCK=$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)
      export PATH=$HOME/src/scripts:$PATH
    '';

    plugins = [
      { name = "zsh-powerlevel9k";
        file = "powerlevel9k.zsh-theme";
        src = pkgs.zsh-powerlevel9k.src;
      }
    ];
  };

  programs.bash = {
    enable = true;

    historySize     = 5000;
    historyFileSize = 50000;
    historyFile     = "${xdg.dataHome}/bash/history";
    historyControl  = [ "ignoredups" "ignorespace" "erasedups" ];
    shellOptions    = [ "histappend" ];

    sessionVariables = {
      INPUTRC = "${xdg.configHome}/bash/input";
    };

    shellAliases = {
      b = "${pkgs.git}/bin/git b";
      l = "${pkgs.git}/bin/git l";
      w = "${pkgs.git}/bin/git w";

      u = "${pkgs.gnumake}/bin/make -C ${home_directory}/src/nix -f Makefile";

      g   = "${pkgs.gitAndTools.hub}/bin/hub";
      git = "${pkgs.gitAndTools.hub}/bin/hub";
      ga  = "${pkgs.gitAndTools.git-annex}/bin/git-annex";

      ls    = "${pkgs.coreutils}/bin/ls --color=auto";
      nm    = "${pkgs.findutils}/bin/find . -name";
      par   = "${pkgs.parallel}/bin/parallel";
      rm    = "${home_directory}/src/scripts/trash";
      rX    = "${pkgs.coreutils}/bin/chmod -R ugo+rX";
      scp   = "${pkgs.rsync}/bin/rsync -aP --inplace";
      hide  = "chflags hidden";
      proc  = "ps axwwww | ${pkgs.gnugrep}/bin/grep -i";
      wipe  = "${pkgs.srm}/bin/srm -vfr";
      nstat = "netstat -nr -f inet"
            + " | ${pkgs.gnugrep}/bin/egrep -v \"(lo0|vmnet|169\\.254|255\\.255)\""
            + " | ${pkgs.coreutils}/bin/tail -n +5";
    };

    profileExtra = ''
      export PATH=${pkgs.coreutils}/bin:$PATH

      for file in ${xdg.configHome}/fetchmail/config \
                  ${xdg.configHome}/fetchmail/config-lists
      do
          cp -pL $file ''${file}.copy
          chmod 0600 ''${file}.copy
      done

      export GPG_TTY=$(tty)
      if ! pgrep -x "gpg-agent" > /dev/null; then
          ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
      fi

      . ${pkgs.z}/share/z.sh

      function rmdir-r() {
          ${pkgs.findutils}/bin/find "$@" -depth -type d -empty \
              -exec ${pkgs.coreutils}/bin/rmdir {} \;
      }
    '';

    bashrcExtra = lib.mkBefore ''
      source /etc/bashrc

      DOCKER_MACHINE=$(which docker-machine)
      if [[ -x "$DOCKER_MACHINE" ]]; then
          if $DOCKER_MACHINE status default > /dev/null 2>&1; then
              eval $($DOCKER_MACHINE env default) > /dev/null 2>&1
          fi
      fi

      export SSH_AUTH_SOCK=$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)
      export PATH=$HOME/src/scripts:$PATH
    '';
  };

  programs.git = {
    enable = true;

    userName  = "John Wiegley";
    userEmail = "johnw@newartisans.com";

    signing = {
      key = "C144D8F4F19FE630";
      signByDefault = false;
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
      ls-ignored = "ls-files --exclude-standard --ignored --others";
      rc         = "rebase --continue";
      rh         = "reset --hard";
      rs         = "rebase --skip";
      ru         = "remote update --prune";
      snap       = "!${pkgs.git}/bin/git stash"
                 + " && ${pkgs.git}/bin/git stash apply";
      snaplog    = "!${pkgs.git}/bin/git log refs/snapshots/refs/heads/"
                 + "\$(${pkgs.git}/bin/git rev-parse HEAD)";
      spull      = "!${pkgs.git}/bin/git stash"
                 + " && ${pkgs.git}/bin/git pull"
                 + " && ${pkgs.git}/bin/git stash pop";
      su         = "submodule update --init";
      undo       = "reset --soft HEAD^";
      w          = "status -sb";
      wdiff      = "diff --color-words";
      l          = "log --graph --pretty=format:'%Cred%h%Creset"
                 + " —%Cblue%d%Creset %s %Cgreen(%cr)%Creset'"
                 + " --abbrev-commit --date=relative --show-notes=*";
    };

    extraConfig = {
      core = {
        editor            = "${pkgs.emacs}/bin/emacsclient";
        trustctime        = false;
        fsyncobjectfiles  = true;
        pager             = "${pkgs.less}/bin/less --tabs=4 -RFX";
        logAllRefUpdates  = true;
        precomposeunicode = false;
        whitespace        = "trailing-space,space-before-tab";
      };

      branch.autosetupmerge = true;
      commit.gpgsign        = false;
      github.user           = "jwiegley";
      credential.helper     = "osxkeychain";
      ghi.token             = "!/usr/bin/security find-internet-password"
                            + " -a jwiegley -s github.com -l 'ghi token' -w";
      hub.protocol          = "https";
      mergetool.keepBackup  = true;
      pull.rebase           = true;
      rebase.autosquash     = true;
      rerere.enabled        = true;

      "merge \"ours\"".driver   = true;
      "magithub \"ci\"".enabled = false;

      http = {
        sslCAinfo = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
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
        recurseSubmodules = "check";
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
        backends = "SHA512E";
        alwayscommit = false;
      };

      "filter \"media\"" = {
        required = true;
        clean = "${pkgs.git}/bin/git media clean %f";
        smudge = "${pkgs.git}/bin/git media smudge %f";
      };

      diff = {
        ignoreSubmodules = "dirty";
        renames = "copies";
        mnemonicprefix = true;
      };

      advice = {
        statusHints = false;
        pushNonFastForward = false;
      };

      "filter \"lfs\"" = {
        clean = "${home_directory}/src/scripts/git-lfs clean -- %f";
        smudge = "${home_directory}/src/scripts/git-lfs smudge --skip -- %f";
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
      "*.elc" "*.vo" "*.aux" "*.v.d" "*.o" "*.a" "*.la" "*.so" "*.dylib"
      "*~" "#*#"
    ];
  };

  programs.ssh = {
    enable = true;

    controlMaster  = "auto";
    controlPath    = "/tmp/ssh-%u-%r@%h:%p";
    controlPersist = "1800";

    forwardAgent = true;
    serverAliveInterval = 60;

    hashKnownHosts = true;
    userKnownHostsFile = "${xdg.configHome}/ssh/known_hosts";

    matchBlocks = rec {
      vulcan.hostname = "192.168.1.69";
      hermes.hostname = "192.168.1.65";
      mybook = vulcan;
      tank = hermes;

      home    = { hostname = "76.234.69.149"; port = 2201; };
      titan   = { hostname = "192.168.1.133"; user = "root"; };
      mohajer = { hostname = "192.168.1.75";  user = "nasimw"; };
      router  = { hostname = "192.168.1.2";   user = "root"; };

      id_local = {
        host = lib.concatStringsSep " " [
          "fiat" "hermes" "home" "mac1*" "mohajer" "mybook" "nixos*"
          "peta" "smokeping" "tails" "tank" "titan" "ubuntu*" "vulcan"
        ];
        identityFile = "${xdg.configHome}/ssh/id_local";
        identitiesOnly = true;
      };

      ubuntu.hostname = "172.16.138.129";
      peta.hostname   = "172.16.138.140";
      fiat.hostname   = "172.16.138.145";

      nixos = {
        hostname     = "192.168.128.132";
        proxyCommand = "${pkgs.openssh}/bin/ssh -q hermes "
                     + "/run/current-system/sw/bin/socat - TCP:%h:%p";
      };

      smokeping = { hostname = "192.168.1.78";   user = "smokeping"; };
      tails     = { hostname = "172.16.138.139"; user = "root"; };
      elpa      = { hostname = "elpa.gnu.org";   user = "root"; };

      savannah.hostname  = "git.sv.gnu.org";
      fencepost.hostname = "fencepost.gnu.org";
      launchpad.hostname = "bazaar.launchpad.net";
      mail.hostname      = "mail.haskell.org";

      haskell_org = { host = "*haskell.org"; user = "root"; };

      ivysaur = {
        hostname = "ivysaur.ait.na.baesystems.com";
        user = "jwiegley";
        identityFile = "${xdg.configHome}/ssh/id_bae";
        identitiesOnly = true;
      };
    };
  };

  programs.browserpass = {
    enable = true;
    browsers = [ "firefox" ];
  };

  programs.home-manager = {
    enable = true;
    path = "${home_directory}/oss/home-manager";
  };

  xdg = {
    enable = true;

    configHome = "${home_directory}/.config";
    dataHome   = "${home_directory}/.local/share";
    cacheHome  = "${home_directory}/.cache";

    configFile."gnupg/gpg-agent.conf".text = ''
      enable-ssh-support
      default-cache-ttl 600
      max-cache-ttl 7200
      pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
      scdaemon-program ${xdg.configHome}/gnupg/scdaemon-wrapper
    '';

    configFile."gnupg/scdaemon-wrapper" = {
      text = ''
        #!/bin/bash
        export DYLD_FRAMEWORK_PATH=/System/Library/Frameworks
        exec ${pkgs.gnupg}/libexec/scdaemon "$@"
      '';
      executable = true;
    };

    configFile."aspell/config".text = ''
      local-data-dir ${pkgs.aspell}/lib/aspell
      data-dir ${pkgs.aspellDicts.en}/lib/aspell
      personal ${xdg.configHome}/aspell/en_US.personal
      repl ${xdg.configHome}/aspell/en_US.repl
    '';

    configFile."msmtp".text = ''
      defaults

      tls on
      tls_starttls on
      tls_trust_file ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

      account fastmail
      host smtp.fastmail.com
      port 587
      auth on
      user ${programs.git.userEmail}
      passwordeval ${pkgs.pass}/bin/pass smtp.fastmail.com
      from ${programs.git.userEmail}
      logfile ${home_directory}/Library/Logs/msmtp.log
    '';

    configFile."fetchmail/config".text = ''
      poll imap.fastmail.com protocol IMAP port 993
        user '${programs.git.userEmail}' there is johnw here
        ssl sslcertck sslcertfile "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        folder INBOX
        fetchall
        mda "${pkgs.dovecot}/libexec/dovecot/dovecot-lda -e"
    '';

    configFile."fetchmail/config-lists".text = ''
      poll imap.fastmail.com protocol IMAP port 993
        user '${programs.git.userEmail}' there is johnw here
        ssl sslcertck sslcertfile "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        folder 'Lists'
        fetchall
        mda "${pkgs.dovecot}/libexec/dovecot/dovecot-lda -e -m list.misc"
    '';
  };
}
