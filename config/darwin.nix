{ config, lib, pkgs, ... }:

let home_directory = "/Users/johnw";
    logdir = "${home_directory}/Library/Logs"; in
{
  system.defaults.NSGlobalDomain.AppleKeyboardUIMode = 3;
  system.defaults.NSGlobalDomain.ApplePressAndHoldEnabled = false;

  system.defaults.dock.autohide    = true;
  system.defaults.dock.launchanim  = false;
  system.defaults.dock.orientation = "right";

  system.defaults.trackpad.Clicking = true;

  networking = {
    dns = [ "127.0.0.1" ];
    search = [ "local" ];
    knownNetworkServices = [ "Ethernet" "Wi-Fi" ];
  };

  launchd.daemons = {
    cleanup = {
      command = "${pkgs.dirscan}/bin/cleanup -u";
      serviceConfig.StartInterval = 86400;
    };

    pdnsd = {
      script = ''
        cp -p /etc/pdnsd.conf /tmp/.pdnsd.conf
        chmod 700 /tmp/.pdnsd.conf
        chown root /tmp/.pdnsd.conf
        ${pkgs.pdnsd}/sbin/pdnsd -c /tmp/.pdnsd.conf
      '';
      serviceConfig.RunAtLoad = true;
      serviceConfig.KeepAlive = true;
    };

    openzfs-InvariantDisks = {
      command = "${pkgs.OpenZFSonOSX}/bin/InvariantDisks";
      serviceConfig.RunAtLoad = true;
      serviceConfig.KeepAlive = true;
    };
    openzfs-zconfigd = {
      command = "${pkgs.OpenZFSonOSX}/bin/zconfigd";
      serviceConfig.RunAtLoad = true;
      serviceConfig.KeepAlive = true;
    };
    openzfs-zed = {
      command = "${pkgs.OpenZFSonOSX}/bin/zed -vfF";
      serviceConfig.RunAtLoad = true;
      serviceConfig.KeepAlive = true;
    };
    openzfs-zpool-import-all = {
      command = "${pkgs.OpenZFSonOSX}/libexec/zfs/launchd.d/zpool-import-all.sh";
      serviceConfig.RunAtLoad = true;
    };
  };

  launchd.user.agents = {
    dovecot = {
      command = "${pkgs.dovecot}/libexec/dovecot/imap -c /etc/dovecot/dovecot.conf";
      serviceConfig.WorkingDirectory = "${pkgs.dovecot}/lib";
      serviceConfig.inetdCompatibility.Wait = "nowait";
      serviceConfig.Sockets.Listeners = {
        SockNodeName = "127.0.0.1";
        SockServiceName = "9143";
      };
    };

    leafnode = {
      command = "${pkgs.leafnode}/sbin/leafnode "
        + "-d ${home_directory}/Messages/Newsdir "
        + "-F ${home_directory}/Messages/leafnode/config";
      serviceConfig.WorkingDirectory = "${pkgs.dovecot}/lib";
      serviceConfig.inetdCompatibility.Wait = "nowait";
      serviceConfig.Sockets.Listeners = {
        SockNodeName = "127.0.0.1";
        SockServiceName = "9119";
      };
    };

    myip = {
      script = ''
        if [[ $(hostname) =~ [Vv]ulcan ]]; then
            cat > ${home_directory}/Documents/home.config <<EOF
Host home
    HostName $(dig +short myip.opendns.com @resolver1.opendns.com.)
    Port 2201
EOF
        fi
      '';
      serviceConfig.StartInterval = 3600;
    };

    rdm = rec {
      script = ''
        ${pkgs.rtags}/bin/rdm \
            --verbose \
            --launchd \
            --inactivity-timeout 300 \
            --socket-file ${serviceConfig.Sockets.Listeners.SockPathName}
            --log-file ${logdir}/rtags.launchd.log
      '';
      serviceConfig.Sockets.Listeners.SockPathName
        = "${home_directory}/.cache/rdm/socket";
    };
  };

  system.activationScripts.postActivation.text = ''
    chflags nohidden ${home_directory}/Library

    sudo launchctl load -w \
        /System/Library/LaunchDaemons/com.apple.atrun.plist > /dev/null 2>&1 \
        || exit 0

    cp -pL /etc/DefaultKeyBinding.dict ${home_directory}/Library/KeyBindings/DefaultKeyBinding.dict
  '';

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
                  (attrNames (readDir path)))
        ++ [ (import ./envs.nix) ];
  };

  environment = {
    systemPackages = with pkgs;
      let exe = haskell.lib.justStaticExecutables; in [
      nixUnstable
      nix-scripts
      nix-prefetch-scripts
      home-manager
      coreutils
      my-scripts

      # gitToolsEnv
      diffstat
      diffutils
      ghi
      gist
      (exe haskPkgs.git-all)
      (exe haskPkgs.git-monitor)
      git-lfs
      git-scripts
      git-tbdiff
      gitRepo
      gitAndTools.git-imerge
      gitAndTools.gitFull
      gitAndTools.gitflow
      gitAndTools.hub
      gitAndTools.tig
      gitAndTools.git-annex
      gitAndTools.git-annex-remote-rclone
      github-backup
      gitstats
      pass-git-helper
      patch
      patchutils
      sift

      # jsToolsEnv
      jq
      jquery
      nodejs
      nodePackages.eslint
      nodePackages.csslint
      nodePackages.js-beautify
      nodePackages.jsontool

      # langToolsEnv
      R
      autoconf
      automake
      (exe haskPkgs.cabal2nix)
      (exe haskPkgs.cabal-install)
      clang
      cmake
      fftw
      fftw.dev
      fftw.man
      fftwFloat
      fftwFloat.dev
      fftwFloat.man
      fftwLongDouble
      fftwLongDouble.dev
      fftwLongDouble.man
      global
      gmp
      gnumake
      (exe haskPkgs.hpack)
      htmlTidy
      idutils
      lean
      libcxx
      libcxxabi
      libtool
      llvm
      lp_solve
      mpfr
      ninja
      ott
      pkgconfig
      rabbitmq-c
      rtags
      sbcl
      sloccount
      verasco
      yamale

      # mailToolsEnv
      contacts
      dovecot
      dovecot_pigeonhole
      fetchmail
      imapfilter
      leafnode
      msmtp

      # networkToolsEnv
      aria2
      backblaze-b2
      bazaar
      cacert
      dnsutils
      httrack
      iperf
      lftp
      mercurialFull
      mitmproxy
      mtr
      nmap
      openssh
      openssl
      openvpn
      pdnsd
      rclone
      rsync
      sipcalc
      socat2pre
      spiped
      sshify
      subversion
      w3m
      wget
      youtube-dl
      znc
      zncModules.fish
      zncModules.push

      # publishToolsEnv
      biber
      ditaa
      dot2tex
      doxygen
      figlet
      fontconfig
      graphviz-nox
      groff
      highlight
      hugo
      inkscape.out
      ledger
      (exe haskPkgs.lhs2tex)
      librsvg
      (exe haskPkgs.pandoc)
      pdf-tools-server
      plantuml
      poppler_utils
      qpdf
      sdcv
      (exe haskPkgs.sitebuilder)
      sourceHighlight
      svg2tikz
      texFull
      # texinfo
      wordnet
      yuicompressor

      # pythonToolsEnv
      python27
      pythonDocs.pdf_letter.python27
      pythonDocs.html.python27
      python27Packages.setuptools
      python27Packages.pygments
      python27Packages.certifi
      python3

      # systemToolsEnv
      aspell
      aspellDicts.en
      bash-completion
      bashInteractive
      browserpass
      dirscan
      ctop
      cvc4
      direnv
      epipe
      exiv2
      fd
      findutils
      fswatch
      fzf
      gawk
      gnugrep
      gnupg
      gnuplot
      gnused
      gnutar
      hammer
      hashdb
      (exe haskPkgs.hours)
      htop
      imagemagickBig
      jdiskreport
      jdk8
      less
      linkdups
      lipotell
      multitail
      mysql
      nix-bash-completions
      nix-zsh-completions
      org2tc
      p7zip
      paperkey
      parallel
      pass
      pass-otp
      pinentry_mac
      postgresql
      (exe haskPkgs.pushme)
      pv
      qemu
      qrencode
      renameutils
      ripgrep
      rlwrap
      (exe haskPkgs.runmany)
      screen
      silver-searcher
      (exe haskPkgs.simple-mirror)
      (exe haskPkgs.sizes)
      smartmontools
      sqlite
      srm
      stow
      terminal-notifier
      time
      tmux
      tree
      tsvutils
      (exe haskPkgs.una)
      unrar
      unzip
      vim
      watch
      xz
      yubico-piv-tool
      yubikey-manager
      yubikey-personalization
      z
      z3
      zbar
      zip
      zsh
      zsh-syntax-highlighting

      # x11ToolsEnv
      # xquartz
      # xorg.xhost
      # xorg.xauth
      # ratpoison

      # Applications
      Anki
      Dash
      DeskzillaLite
      Docker
      Firefox
      GIMP
      HandBrake
      KeyboardMaestro
      # LaTeXiT
      # LaunchBar
      OpenZFSonOSX
      PathFinder
      PhoneView
      RipIt
      #SageMath
      Skim
      Soulver
      SuspiciousPackage
      # Transmission
      Ukelele
      UnicodeChecker
      VLC
      VirtualII
      Zekr
      Zotero
      iTerm2
    ];

    systemPath = [
      "${pkgs.Docker}/Applications/Docker.app/Contents/Resources/bin"
    ];

    variables = {
      HOME_MANAGER_CONFIG = "${home_directory}/src/nix/config/home.nix";

      PASSWORD_STORE_ENABLE_EXTENSIONS = "true";
      PASSWORD_STORE_EXTENSIONS_DIR =
        "${config.system.path}/lib/password-store/extensions";

      MANPATH = [
        "${home_directory}/.nix-profile/share/man"
        "${home_directory}/.nix-profile/man"
        "${config.system.path}/share/man"
        "${config.system.path}/man"
        "/usr/local/share/man"
        "/usr/share/man"
        "/Developer/usr/share/man"
        "/usr/X11/man"
      ];

      LC_CTYPE     = "en_US.UTF-8";
      LESSCHARSET  = "utf-8";
      LEDGER_COLOR = "true";
      PAGER        = "less";
    };

    shellAliases = {
      rehash = "hash -r";
    };

    pathsToLink = [ "/info" "/etc" "/share" "/include" "/lib" "/libexec" ];

    etc."dovecot/dovecot.conf".text = ''
      auth_mechanisms = plain
      disable_plaintext_auth = no
      lda_mailbox_autocreate = yes
      log_path = syslog
      mail_gid = 20
      mail_location = mdbox:${home_directory}/Messages/Mailboxes
      mail_plugin_dir = ${config.system.path}/lib/dovecot
      mail_plugins = fts fts_lucene zlib
      mail_uid = 501
      postmaster_address = postmaster@newartisans.com
      protocols = imap
      sendmail_path = ${pkgs.msmtp}/bin/sendmail
      ssl = no
      syslog_facility = mail

      protocol lda {
        mail_plugins = $mail_plugins sieve
      }
      userdb {
        driver = prefetch
      }

      passdb {
        driver = static
        args = uid=501 gid=20 home=${home_directory} password=pass
      }

      namespace {
        type = private
        separator = .
        prefix =
        location =
        inbox = yes
        subscriptions = yes
      }

      plugin {
        fts = lucene
        fts_squat = partial=4 full=10

        fts_lucene = whitespace_chars=@.
        fts_autoindex = yes

        zlib_save_level = 6
        zlib_save = gz
      }
      plugin {
        sieve_extensions = +editheader
        sieve = ${home_directory}/Messages/dovecot.sieve
        sieve_dir = ${home_directory}/Messages/sieve
      }
    '';

    etc."pdnsd.conf".text = ''
      global {
          perm_cache   = 8192;
          cache_dir    = "/Library/Caches/pdnsd";
          run_as       = "johnw";
          server_ip    = 127.0.0.1;
          status_ctl   = on;
          query_method = udp_tcp;
          min_ttl      = 1h;    # Retain cached entries at least 1 hour.
          max_ttl      = 4h;    # Four hours.
          timeout      = 10;    # Global timeout option (10 seconds).
          udpbufsize   = 1024;  # Upper limit on the size of UDP messages.
          neg_rrs_pol  = on;
          par_queries  = 1;
      }

      server {
          label       = "google";
          ip          = 8.8.8.8, 8.8.4.4;
          preset      = on;
          uptest      = none;
          edns_query  = yes;
          exclude     = ".local";
          proxy_only  = on;
          purge_cache = off;
      }

      server {
          label       = "dyndns";
          ip          = 216.146.35.35, 216.146.36.36;
          preset      = on;
          uptest      = none;
          edns_query  = yes;
          exclude     = ".local";
          proxy_only  = on;
          purge_cache = off;
      }

      # The servers provided by OpenDNS are fast, but they do not reply with
      # NXDOMAIN for non-existant domains, instead they supply you with an address
      # of one of their search engines. They also lie about the addresses of the
      # search engines of google, microsoft and yahoo. If you do not like this
      # behaviour the "reject" option may be useful.
      server {
          label       = "opendns";
          ip          = 208.67.222.222, 208.67.220.220;
          # You may need to add additional address ranges here if the addresses
          # of their search engines change.
          reject      = 208.69.32.0/24,
                        208.69.34.0/24,
                        208.67.219.0/24;
          preset      = on;
          uptest      = none;
          edns_query  = yes;
          exclude     = ".local";
          proxy_only  = on;
          purge_cache = off;
      }

      # This section is meant for resolving from root servers.
      server {
          label             = "root-servers";
          root_server       = discover;
          ip                = 198.41.0.4, 192.228.79.201;
          randomize_servers = on;
      }

      source {
          owner         = localhost;
          serve_aliases = on;
          file          = "/etc/hosts";
      }

      rr {
          name    = localhost;
          reverse = on;
          a       = 127.0.0.1;
          owner   = localhost;
          soa     = localhost,root.localhost,42,86400,900,86400,86400;
      }

      rr { name = localunixsocket;       a = 127.0.0.1; }
      rr { name = localunixsocket.local; a = 127.0.0.1; }
      # rr { name = bugs.ledger-cli.org;   a = 172.16.138.147; }
      rr { name = bugs.ledger-cli.org;   a = 192.168.128.132; }

      neg {
          name  = doubleclick.net;
          types = domain;           # This will also block xxx.doubleclick.net, etc.
      }

      neg {
          name  = bad.server.com;   # Badly behaved server you don't want to connect to.
          types = A,AAAA;
      }
    '';

    etc."DefaultKeyBinding.dict".text = ''
      {
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
      }
    '';
  };

  services.nix-daemon.enable = true;
  services.activate-system.enable = true;

  nix = {
    package = pkgs.nixUnstable;

    nixPath =
      [ "darwin-config=$HOME/src/nix/config/darwin.nix"
        "home-manager=$HOME/src/nix/home-manager"
        "darwin=$HOME/src/nix/darwin"
        "nixpkgs=$HOME/src/nix/nixpkgs"
      ];

    trustedUsers = [ "johnw" "@admin" ];
    maxJobs = 4;
    # useSandbox = true;
    distributedBuilds = false;
    # buildMachines = [
    #   { hostName = "hermes";
    #     sshUser = "johnw";
    #     sshKey = "${home_directory}/.config/ssh/id_local";
    #     system = "x86_64-darwin";
    #     maxJobs = 4;
    #   }
    #   # { hostName = "nixos";
    #   #   sshUser = "johnw";
    #   #   sshKey = "${home_directory}/.config/ssh/id_local";
    #   #   system = "x86_64-linux";
    #   #   maxJobs = 2;
    #   # }
    # ];

    binaryCaches = [
      # "https://nixcache.reflex-frp.org"
      "file:///Volumes/tank/Cache"
    ];
    # binaryCachePublicKeys = [
    #   "ryantrinkle.com-1:JJiAKaRv9mWgpVAz8dwewnZe0AzzEAzPkagE9SP5NWI="
    # ];

    extraOptions = ''
      gc-keep-outputs = true
      gc-keep-derivations = true
      env-keep-derivations = true
    '';
  };

  programs.bash.enable = true;

  programs.zsh = {
    enable = true;
    enableFzfCompletion = true;
    enableFzfGit = true;
    enableFzfHistory = true;
    enableSyntaxHighlighting = true;
  };

  programs.nix-index.enable = true;

  system.stateVersion = 2;
}
