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
      command = "${home_directory}/bin/cleanup -u";
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

    privoxy = {
      script = "${pkgs.privoxy}/bin/privoxy --no-daemon /etc/privoxy/config";
      serviceConfig.RunAtLoad = true;
      serviceConfig.KeepAlive = true;
    };

    syncthing = {
      script = "sudo -u johnw ${pkgs.syncthing}/bin/syncthing -no-browser -no-restart";
      environment.STNORESTART = "1";
      serviceConfig.RunAtLoad = true;
      serviceConfig.KeepAlive = true;
      serviceConfig.ProcessType = "Background";
      serviceConfig.LowPriorityIO = true;
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

    languagetool = {
      script = ''
        ${pkgs.jdk8}/bin/java                                      \
            -cp ${pkgs.languagetool}/share/languagetool-server.jar \
            org.languagetool.server.HTTPServer                     \
            --port 8099 --allow-origin "*"
      '';
      serviceConfig.RunAtLoad = true;
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

  environment.etc."dovecot/dovecot.conf".text = ''
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

  environment.etc."privoxy/config".text = ''
    user-manual ${pkgs.privoxy}/share/doc/privoxy/user-manual/
    confdir ${pkgs.privoxy}/etc
    logdir ${pkgs.privoxy}/var/log/privoxy
    actionsfile /etc/privoxy/match-all.action
    actionsfile default.action
    actionsfile user.action
    filterfile default.filter
    filterfile user.filter
    logfile logfile
    listen-address 127.0.0.1:8118
    toggle 1
    enable-remote-toggle 0
    enable-remote-http-toggle 0
    enable-edit-actions 0
    enforce-blocks 0
    buffer-limit 4096
    enable-proxy-authentication-forwarding 0
    forwarded-connect-retries  0
    accept-intercepted-requests 0
    allow-cgi-request-crunching 0
    split-large-forms 0
    keep-alive-timeout 5
    tolerate-pipelining 1
    socket-timeout 300
  '';

  environment.etc."privoxy/match-all.action".text = ''
    {+change-x-forwarded-for{block} \
     +client-header-tagger{css-requests} \
     +client-header-tagger{image-requests} \
     +client-header-tagger{range-requests} \
     +deanimate-gifs{last} \
     +filter{refresh-tags} \
     +filter{img-reorder} \
     +filter{banners-by-size} \
     +filter{webbugs} \
     +filter{jumping-windows} \
     +filter{ie-exploits} \
     +hide-from-header{block} \
     +hide-referrer{conditional-block} \
     +session-cookies-only \
     +set-image-blocker{pattern} \
    }
    / # Match all URLs
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
    source ${home_directory}/.bash_profile
    dir=$(dirname "$0")
    name=$(basename "$0")
    exec "$dir"/."$name" "$@"
  '';

  system.activationScripts.postActivation.text = ''
    chflags nohidden ${home_directory}/Library

    sudo launchctl load -w \
        /System/Library/LaunchDaemons/com.apple.atrun.plist > /dev/null 2>&1 \
        || exit 0

    cp -pL /etc/DefaultKeyBinding.dict ${home_directory}/Library/KeyBindings/DefaultKeyBinding.dict

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
  };

  nixpkgs.overlays =
    let path = ../overlays; in with builtins;
    map (n: import (path + ("/" + n)))
        (filter (n: match ".*\\.nix" n != null ||
                    pathExists (path + ("/" + n + "/default.nix")))
                (attrNames (readDir path)));

  environment.systemPackages = with pkgs; [
    nixUnstable
    nix-scripts
    nix-prefetch-scripts
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
    R
    autoconf
    automake
    clang
    cmake
    global
    gmp
    gnumake
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
    (haskell.lib.justStaticExecutables haskPkgs.nixfmt)

    # mailToolsEnv
    dovecot
    dovecot_pigeonhole
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
    openvpn
    pdnsd
    privoxy
    rclone
    rsync
    sipcalc
    socat2pre
    spiped
    subversion
    syncthing
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
    aspell
    aspellDicts.en
    bashInteractive
    bash-completion
    bash-z
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
    htop
    imagemagickBig
    jdk8
    less
    multitail
    mysql
    p7zip
    pass
    pass-otp
    parallel
    pinentry_mac
    postgresql
    privoxy
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
    vim
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

  environment.pathsToLink = [ "/info" "/etc" "/share" "/lib" "/libexec" ];

  environment.variables = {
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
    GIT_PAGER    = "less";
  };

  environment.shellAliases = {
    rehash  = "hash -r";
    snaplog = "${pkgs.git}/bin/git log refs/snapshots/\\$(${pkgs.git}/bin/git symbolic-ref HEAD)";
    darwin  = "darwin-rebuild switch";
    home    = "${pkgs.home-manager}/bin/home-manager switch";
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

    trustedUsers = [ "@admin" ];
    maxJobs = 4;
    # useSandbox = true;
    distributedBuilds = true;
    buildMachines = [
      { hostName = "hermes";
        sshUser = "johnw";
        sshKey = "${home_directory}/.config/ssh/id_local";
        system = "x86_64-darwin";
        maxJobs = 2;
      }
    ];

    binaryCaches = [
      "https://cache.nixos.org/"
      "https://nixcache.reflex-frp.org"
    ];
    binaryCachePublicKeys = [
      "ryantrinkle.com-1:JJiAKaRv9mWgpVAz8dwewnZe0AzzEAzPkagE9SP5NWI="
    ];

    extraOptions = ''
      gc-keep-outputs = true
      gc-keep-derivations = true
      env-keep-derivations = true
    '';
  };

  programs.bash.enable = true;
  programs.nix-index.enable = true;

  system.stateVersion = 2;
}
