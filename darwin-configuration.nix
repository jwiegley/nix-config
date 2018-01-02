{ config, lib, pkgs, ... }:
{
  system.defaults.NSGlobalDomain.AppleKeyboardUIMode = 3;
  system.defaults.NSGlobalDomain.ApplePressAndHoldEnabled = false;

  system.defaults.dock.autohide    = true;
  system.defaults.dock.launchanim  = false;
  system.defaults.dock.orientation = "right";

  system.defaults.trackpad.Clicking = true;

  launchd.daemons = {
    cleanup = {
      command = "/Users/johnw/bin/cleanup -u";
      serviceConfig.StartInterval = 86400;
    };

    pdnsd = {
      script = ''
        cp -p ${pkgs.johnw-home}/etc/pdnsd.conf /tmp/.pdnsd.conf
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
      command = "${pkgs.leafnode}/sbin/leafnode -d ~/Messages/Newsdir -F ~/Messages/leafnode/config";
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
            --log-file ~/Library/Logs/rtags.launchd.log
      '';
      serviceConfig.Sockets.Listeners.SockPathName = "/Users/johnw/.rdm";
    };

    # znc = {
    #   command = "${pkgs.znc}/bin/znc";
    #   serviceConfig.RunAtLoad = true;
    # };
  };

  environment.etc."per-user/johnw/aspell.conf".text = ''
    data-dir ${pkgs.aspell}/lib/aspell
  '';

  environment.etc."per-user/johnw/scdaemon-wrapper".text = ''
    #!/bin/bash
    export DYLD_FRAMEWORK_PATH=/System/Library/Frameworks
    exec ${pkgs.gnupg}/libexec/scdaemon "$@"
  '';

  environment.etc."per-user/johnw/gpg-agent.conf".text = ''
    enable-ssh-support
    default-cache-ttl 600
    max-cache-ttl 7200
    pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
    scdaemon-program /Users/johnw/.gnupg/scdaemon-wrapper
  '';

  environment.etc."per-user/johnw/com.dannyvankooten.browserpass.json".text = ''
    {
      "name": "com.dannyvankooten.browserpass",
      "description": "Browserpass binary for the Firefox extension",
      "path": "${pkgs.browserpass}/bin/browserpass",
      "type": "stdio",
      "allowed_extensions": [
        "browserpass@maximbaz.com"
      ]
    }
  '';

  environment.etc."msmtp.conf".text = ''
    defaults

    tls on
    tls_starttls on
    tls_trust_file ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    account fastmail
    host smtp.fastmail.com
    port 587
    auth on
    user johnw@newartisans.com
    passwordeval pass smtp.fastmail.com
    from johnw@newartisans.com
    logfile /Library/Logs/msmtp.log
  '';

  environment.etc."dovecot/dovecot.conf".text = ''
    auth_mechanisms = plain
    disable_plaintext_auth = no
    lda_mailbox_autocreate = yes
    log_path = syslog
    mail_gid = 20
    mail_location = mdbox:/Users/johnw/Messages/Mailboxes
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
      args = uid=501 gid=20 home=/Users/johnw password=pass
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
      sieve = ~/Messages/dovecot.sieve
      sieve_dir = ~/Messages/sieve
    }
  '';

  environment.etc."fetchmailrc".text = ''
    poll imap.fastmail.com protocol IMAP port 993
      user 'johnw@newartisans.com' there is johnw here
      ssl sslcertck sslcertfile "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      folder INBOX
      fetchall
      mda "${pkgs.dovecot}/libexec/dovecot/dovecot-lda -e"
  '';

  environment.etc."fetchmailrc.lists".text = ''
    poll imap.fastmail.com protocol IMAP port 993
      user 'johnw@newartisans.com' there is johnw here
      ssl sslcertck sslcertfile "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      folder 'Lists'
      fetchall
      mda "${pkgs.dovecot}/libexec/dovecot/dovecot-lda -e -m list.misc"
  '';

  system.activationScripts.extraActivation.text = ''
    chflags nohidden ~/Library

    chown johnw /etc/static/fetchmailrc
    chmod 0700 /etc/static/fetchmailrc
    chown johnw /etc/static/fetchmailrc.lists
    chmod 0700 /etc/static/fetchmailrc.lists

    for i in                                    \
        /etc/static/per-user/johnw/aspell.conf  \
        ${pkgs.johnw-home}/dot-files/*
    do
        ln -sf $i ~/.$(basename $i)
    done

    ln -sf ${pkgs.dot-emacs}/emacs.d/compiled ~/.emacs.d/compiled

    mkdir -p ~/.parallel
    touch ~/.parallel/will-cite

    git config --global http.sslCAinfo "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    git config --global http.sslverify true

    cp -p /etc/static/per-user/johnw/scdaemon-wrapper ~/.gnupg
    chmod +x ~/.gnupg/scdaemon-wrapper

    cp -p /etc/static/per-user/johnw/gpg-agent.conf ~/.gnupg
    ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent

    for file in                                           \
        Library/KeyBindings/DefaultKeyBinding.dict        \
        Library/Keyboard\ Layouts/PersianDvorak.keylayout \
        Library/Scripts
    do
        dir=$(dirname "$file")
        mkdir -p ~/"$dir"
        ln -sf "${pkgs.johnw-home}/$file" ~/"$file"
    done

    for file in \
        Library/Application\ Support/Mozilla/NativeMessagingHosts/com.dannyvankooten.browserpass.json
    do
        dir=$(dirname "$file")
        mkdir -p ~/"$dir"
        ln -sf "/etc/per-user/johnw/$(basename "$file")" ~/"$file"
    done
  '';

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowBroken = true;

  nixpkgs.config.packageOverrides = pkgs: import ./overrides.nix { pkgs = pkgs; };

  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = with pkgs; [
    nix-prefetch-scripts
    nix-repl
    nix-scripts

    coreutils
    johnw-home
    johnw-scripts
    dot-emacs

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
    sourceHighlight
    # texinfo
    yuicompressor
    (haskell.lib.justStaticExecutables haskPkgs.lhs2tex)
    (haskell.lib.justStaticExecutables haskPkgs.sitebuilder)
    texFull

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
    imagemagick_light
    jdk8
    jenkins
    less
    multitail
    renameutils
    p7zip
    pass
    parallel
    pinentry_mac
    postgresql96
    pv
    # jww (2017-12-26): Waiting on https://bugs.launchpad.net/qemu/+bug/1714750
    # qemu
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
    zip
    zsh
  ];

  # Create /etc/bashrc that loads the nix-darwin environment.
  programs.bash.enable = true;

  # Recreate /run/current-system symlink after boot.
  services.nix-daemon.enable = true;
  services.activate-system.enable = true;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 2;

  # You should generally set this to the total number of logical cores in your
  # system. (sysctl -n hw.ncpu)
  nix.maxJobs = 4;
  nix.nixPath =
    [ # Use local nixpkgs checkout instead of channels.
      "darwin-config=$HOME/src/nix/darwin-configuration.nix"
      "darwin=$HOME/oss/darwin"
      "nixpkgs=$HOME/oss/nixpkgs"
      "nixpkgs-next=$HOME/oss/nixpkgs-next"
      "$HOME/.nix-defexpr/channels"
    ];

  nix.extraOptions = ''
    gc-keep-outputs = true
    gc-keep-derivations = true
    env-keep-derivations = true
  '';

  programs.nix-index.enable = true;
}
