{ config, lib, pkgs, ... }:

let home = "/Users/johnw"; in
{
  system.defaults.NSGlobalDomain.AppleKeyboardUIMode = 3;
  system.defaults.NSGlobalDomain.ApplePressAndHoldEnabled = false;

  system.defaults.dock.autohide    = true;
  system.defaults.dock.launchanim  = false;
  system.defaults.dock.orientation = "right";

  system.defaults.trackpad.Clicking = true;

  launchd.daemons = {
    cleanup = {
      command = "${home}/bin/cleanup -u";
      serviceConfig.StartInterval = 86400;
    };

    collectgarbage = {
      command = "${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 14d";
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
        + "-d ${home}/Messages/Newsdir "
        + "-F ${home}/Messages/leafnode/config";
      serviceConfig.WorkingDirectory = "${pkgs.dovecot}/lib";
      serviceConfig.inetdCompatibility.Wait = "nowait";
      serviceConfig.Sockets.Listeners = {
        SockNodeName = "127.0.0.1";
        SockServiceName = "9119";
      };
    };

    languagetool = {
      script = ''
        ${pkgs.jdk8}/bin/java                                      \
            -cp ${pkgs.languagetool}/share/languagetool-server.jar \
            org.languagetool.server.HTTPServer                     \
            --port 8099 --allow-origin "*"
      '';
      serviceConfig.RunAtLoad = true;
    };

    rdm = {
      script = ''
        ${pkgs.rtags}/bin/rdm \
            --verbose \
            --launchd \
            --inactivity-timeout 300 \
            --log-file ${home}/Library/Logs/rtags.launchd.log
      '';
      serviceConfig.Sockets.Listeners.SockPathName = "${home}/.rdm";
    };
  };

  environment.etc."dovecot/dovecot.conf".text = ''
    auth_mechanisms = plain
    disable_plaintext_auth = no
    lda_mailbox_autocreate = yes
    log_path = syslog
    mail_gid = 20
    mail_location = mdbox:${home}/Messages/Mailboxes
    mail_plugin_dir = ${pkgs.dovecot-plugins}/etc/dovecot/modules
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
      args = uid=501 gid=20 home=${home} password=pass
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
      sieve = ${home}/Messages/dovecot.sieve
      sieve_dir = ${home}/Messages/sieve
    }
  '';

  environment.etc."pdnsd.conf".text = ''
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

    neg {
        name  = doubleclick.net;
        types = domain;           # This will also block xxx.doubleclick.net, etc.
    }

    neg {
        name  = bad.server.com;   # Badly behaved server you don't want to connect to.
        types = A,AAAA;
    }
  '';

  environment.etc."DefaultKeyBinding.dict".text = ''
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

  environment.etc."firefox-wrapper".text = ''
    #!/bin/bash
    source /etc/bashrc
    source ${home}/.bash_profile
    dir=$(dirname "$0")
    name=$(basename "$0")
    exec "$dir"/."$name" "$@"
  '';

  system.activationScripts.extraPostActivation.text = ''
    chflags nohidden ${home}/Library

    sudo launchctl load -w \
        /System/Library/LaunchDaemons/com.apple.atrun.plist > /dev/null 2>&1 \
        || exit 0

    cp -pL /etc/DefaultKeyBinding.dict ${home}/Library/KeyBindings/DefaultKeyBinding.dict

    mkdir -p ${home}/.parallel
    touch ${home}/.parallel/will-cite

    if [[ ! -f /Applications/Firefox.app/Contents/MacOS/.firefox ]]; then
        mv /Applications/Firefox.app/Contents/MacOS/firefox \
           /Applications/Firefox.app/Contents/MacOS/.firefox
        mv /Applications/Firefox.app/Contents/MacOS/firefox-bin \
           /Applications/Firefox.app/Contents/MacOS/.firefox-bin
        cp -pL /etc/firefox-wrapper /Applications/Firefox.app/Contents/MacOS/firefox
        chmod +x /Applications/Firefox.app/Contents/MacOS/firefox
        cp -pL /etc/firefox-wrapper /Applications/Firefox.app/Contents/MacOS/firefox-bin
        chmod +x /Applications/Firefox.app/Contents/MacOS/firefox-bin
    fi
  '';

  nixpkgs.config = {
    allowUnfree = true;
    allowBroken = true;

    packageOverrides = pkgs: import ./overrides.nix { pkgs = pkgs; };
  };

  environment.systemPackages = with pkgs; [
    nixUnstable
    nix-scripts
    home-manager
    coreutils

    # gitToolsEnv
    diffstat
    diffutils
    ghi
    gist
    git-scripts
    gitRepo
    gitAndTools.git-imerge
    gitAndTools.gitFull
    gitAndTools.gitflow
    gitAndTools.hub
    gitAndTools.tig
    gitAndTools.git-annex
    gitAndTools.git-annex-remote-rclone
    (haskell.lib.justStaticExecutables haskPkgs.git-all)
    (haskell.lib.justStaticExecutables haskPkgs.git-monitor)
    patch
    patchutils

    # jsToolsEnv
    jq
    nodejs
    nodePackages.eslint
    nodePackages.csslint
    nodePackages.jsontool
    jquery

    # langToolsEnv
    global
    (haskell.lib.justStaticExecutables haskPkgs.bench)
    (haskell.lib.justStaticExecutables haskPkgs.hpack)
    autoconf
    automake
    libtool
    pkgconfig
    clang
    libcxx
    libcxxabi
    llvm
    cmake
    ninja
    gnumake
    rabbitmq-c
    lp_solve
    cabal2nix
    cabal-install
    rtags
    gmp
    mpfr
    htmlTidy
    idutils
    lean
    ott
    R
    sbcl
    sloccount
    verasco

    # mailToolsEnv
    dovecot
    dovecot-plugins
    contacts
    fetchmail
    imapfilter
    leafnode
    msmtp

    # networkToolsEnv
    aria2
    backblaze-b2
    bazaar
    cacert
    httrack
    mercurialFull
    iperf
    nmap
    lftp
    mtr
    dnsutils
    openssh
    openssl
    pdnsd
    privoxy
    rclone
    rsync
    sipcalc
    socat2pre
    spiped
    subversion
    w3m
    wget
    youtube-dl
    znc
    zncModules.fish
    zncModules.push

    # publishToolsEnv
    hugo
    biber
    dot2tex
    doxygen
    graphviz-nox
    highlight
    languagetool
    ledger
    pdf-tools-server
    poppler
    sdcv
    sourceHighlight
    # texinfo
    yuicompressor
    (haskell.lib.justStaticExecutables haskPkgs.lhs2tex)
    (haskell.lib.justStaticExecutables haskPkgs.sitebuilder)
    texFull
    wordnet

    # pythonToolsEnv
    python3
    python27
    pythonDocs.pdf_letter.python27
    pythonDocs.html.python27
    python27Packages.setuptools
    python27Packages.pygments
    python27Packages.certifi

    # systemToolsEnv
    apg
    aspell
    aspellDicts.en
    bashInteractive
    bash-completion
    nix-bash-completions
    browserpass
    ctop
    direnv
    exiv2
    findutils
    fzf
    gawk
    gnugrep
    gnupg
    paperkey
    gnuplot
    gnused
    gnutar
    (haskell.lib.justStaticExecutables haskPkgs.hours)
    (haskell.lib.justStaticExecutables haskPkgs.pushme)
    (haskell.lib.justStaticExecutables haskPkgs.runmany)
    (haskell.lib.justStaticExecutables haskPkgs.simple-mirror)
    (haskell.lib.justStaticExecutables haskPkgs.sizes)
    (haskell.lib.justStaticExecutables haskPkgs.una)
    imagemagickBig
    jdk8
    jenkins
    less
    multitail
    p7zip
    pass
    pass-otp
    parallel
    pinentry_mac
    postgresql96
    pv
    qemu
    qrencode
    renameutils
    ripgrep
    rlwrap
    screen
    silver-searcher
    srm
    sqlite
    stow
    time
    tmux
    tree
    unrar
    unzip
    watch
    xz
    z3
    cvc4
    zbar
    zip
    zsh

    # x11ToolsEnv
    # xquartz
    # xorg.xhost
    # xorg.xauth
    # ratpoison
  ];

  programs.bash.enable = true;

  services.nix-daemon.enable = true;
  services.activate-system.enable = true;

  system.stateVersion = 2;

  nix.package = pkgs.nixUnstable;
  nix.nixPath =
    [ "darwin-config=$HOME/src/nix/darwin-configuration.nix"
      "home-manager=$HOME/oss/home-manager"
      "darwin=$HOME/oss/darwin"
      "nixpkgs=$HOME/oss/nixpkgs"
      "$HOME/.nix-defexpr/channels"
    ];

  nix.trustedUsers = [ "johnw" ];
  nix.extraOptions = ''
    gc-keep-outputs = true
    gc-keep-derivations = true
    env-keep-derivations = true
  '';

  nix.maxJobs = 8;
  nix.distributedBuilds = true;
  nix.buildMachines = [
    { hostName = "hermes";
      sshUser = "johnw";
      sshKey = "${home}/.config/ssh/id_local";
      system = "x86_64-darwin";
      maxJobs = 4;
    }
  ];

  programs.nix-index.enable = true;

  environment.pathsToLink = [ "/info" "/etc" "/share" "/lib" "/libexec" ];

  environment.variables = {
    HOME_MANAGER_CONFIG = "${home}/src/nix/home-configuration.nix";

    PASSWORD_STORE_ENABLE_EXTENSIONS = "true";
    PASSWORD_STORE_EXTENSIONS_DIR =
      "/run/current-system/sw/lib/password-store/extensions";

    MANPATH = [
      "${home}/.nix-profile/share/man"
      "${home}/.nix-profile/man"
      "/run/current-system/sw/share/man"
      "/run/current-system/sw/man"
      "/usr/local/share/man"
      "/usr/share/man"
      "/Developer/usr/share/man"
      "/usr/X11/man"
    ];

    LC_CTYPE     = "en_US.UTF-8";
    LESSCHARSET  = "utf-8";
    LEDGER_COLOR = "true";
    PAGER        = "less";
    GIT_PAGER    = "less";

    STARDICT_DATA_DIR  = "${home}/oss/dictionaries";
  };

  environment.shellAliases = {
    rehash  = "hash -r";
    snaplog = "git log refs/snapshots/\\$(git symbolic-ref HEAD)";
  };
}
