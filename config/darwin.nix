{ config, lib, pkgs, ... }:

let home_directory = "/Users/johnw";
    xdg_configHome = "${home_directory}/.config";
    log_directory = "${home_directory}/Library/Logs";
    tmp_directory = "/tmp";
    localconfig = import <localconfig>;

in {
  system.defaults = {
    NSGlobalDomain = {
      AppleKeyboardUIMode = 3;
      ApplePressAndHoldEnabled = false;
    };

    dock = {
      autohide    = true;
      launchanim  = false;
      orientation = "right";
    };

    trackpad.Clicking = true;
  };

  networking = {
    dns = [ "127.0.0.1" ];
    search = [ "local" ];
    knownNetworkServices = [ "Ethernet" "Wi-Fi" ];
  };

  launchd.daemons =
    let iterate = interval: {
        LowPriorityIO = true;
        Nice = 5;
        StartInterval = interval;
        # StartCalendarInterval.Hour = 3;
        AbandonProcessGroup = true;
      }; in {

    cleanup = {
      script = ''
        export PYTHONPATH=$PYTHONPATH:${pkgs.dirscan}/libexec
        ${pkgs.dirscan}/bin/cleanup -u >> /var/log/cleanup.log 2>&1
      '';
      serviceConfig = iterate 86400;
    };

    limit-maxfiles = {
      command = "/bin/launchctl limit maxfiles 524288 524288";
      serviceConfig.RunAtLoad = true;
    };

    limit-maxproc = {
      command = "/bin/launchctl limit maxproc 2048 2048";
      serviceConfig.RunAtLoad = true;
    };

    locate = {
      script = ''
        export PATH=$PATH:${pkgs.findutils}/bin
        export HOME=/Users/johnw
        ${pkgs.my-scripts}/bin/update.locate >> /var/log/locate.log 2>&1
      '';
      serviceConfig = iterate 86400;
    };

    pdnsd = {
      script = ''
        cp -pL /etc/pdnsd.conf ${tmp_directory}/.pdnsd.conf
        chmod 700 ${tmp_directory}/.pdnsd.conf
        chown root ${tmp_directory}/.pdnsd.conf
        touch /Library/Caches/pdnsd/pdnsd.cache
        ${pkgs.pdnsd}/sbin/pdnsd -c ${tmp_directory}/.pdnsd.conf
      '';
      serviceConfig.RunAtLoad = true;
      serviceConfig.KeepAlive = true;
    };
  } //
  (if localconfig.hostname == "fin" then {
    snapshots-tank = {
      script = ''
        export PATH=$PATH:${pkgs.my-scripts}/bin:/usr/local/bin
        snapshots tank >> /var/log/snapshots.log 2>&1
      '';
      serviceConfig = iterate 86400;
    };
   } else {});

  launchd.user.agents =
    let iterate = interval: {
        LowPriorityIO = true;
        Nice = 5;
        StartInterval = interval;
        # StartCalendarInterval.Hour = 3;
        AbandonProcessGroup = true;
      }; in {

    aria2c = {
      command = "${pkgs.aria2}/bin/aria2c --enable-rpc";
      serviceConfig.RunAtLoad = true;
    };

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

    rdm = rec {
      script = ''
        ${pkgs.rtags}/bin/rdm \
            --verbose \
            --launchd \
            --inactivity-timeout 300 \
            --socket-file ${serviceConfig.Sockets.Listeners.SockPathName}
            --log-file ${log_directory}/rtags.launchd.log
      '';
      serviceConfig.Sockets.Listeners.SockPathName
        = "${home_directory}/.cache/rdm/socket";
    };
  } //
  (if localconfig.hostname == "fin" then {
     # b2-sync = {
     #   script = ''
     #     export PATH=$PATH:${pkgs.my-scripts}/bin
     #     export PATH=$PATH:${pkgs.backblaze-b2}/bin
     #     export PATH=$PATH:${pkgs.rclone}/bin
     #     if [[ -d /Volumes/tank/Backups ]]; then
     #         ${pkgs.my-scripts}/bin/b2-sync /Volumes/tank tank \
     #             >> /var/log/b2-sync.log 2>&1
     #     fi
     #   '';
     #   serviceConfig = iterate 86400;
     # };
   }
   else if localconfig.hostname == "vulcan" then {
     myip = {
       script = ''
         cat > ${home_directory}/Documents/home.config <<EOF
Host home
    HostName $(${pkgs.dnsutils}/bin/dig +short myip.opendns.com @resolver1.opendns.com.)
    Port 2201
EOF
       '';
       serviceConfig.StartInterval = 3600;
     };
   } else {});

  system.activationScripts.postActivation.text = ''
    chflags nohidden ${home_directory}/Library

    sudo launchctl load -w \
        /System/Library/LaunchDaemons/com.apple.atrun.plist > /dev/null 2>&1 \
        || exit 0

    cp -pL /etc/DefaultKeyBinding.dict \
       ${home_directory}/Library/KeyBindings/DefaultKeyBinding.dict
  '';

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowBroken = false;
      allowUnsupportedSystem = false;
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
    systemPackages = import ./packages.nix { inherit pkgs; };

    systemPath = [
      "${pkgs.Docker}/Applications/Docker.app/Contents/Resources/bin"
    ];

    variables = {
      HOME_MANAGER_CONFIG = "${home_directory}/src/nix/config/home.nix";

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

      PYTHONPATH   = "${pkgs.dirscan}/libexec";
      LC_CTYPE     = "en_US.UTF-8";
      LESSCHARSET  = "utf-8";
      LEDGER_COLOR = "true";
      PAGER        = "less";

      TERM = "xterm-256color";
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

      rr { name = hydra.dfinity.systems;     a = 10.20.12.55; }
      rr { name = nix.dfinity.systems;       a = 10.20.12.55; }
      rr { name = docker.oregon.dfinity.internal; a = 10.20.7.236; }

      server {
          label       = "google";
          ip          = 8.8.8.8, 8.8.4.4;
          preset      = on;
          uptest      = none;
          edns_query  = yes;
          exclude     = ".local";
          include     = "vpn.dfinity.systems";
          exclude     = ".dfinity.build";
          exclude     = ".dfinity.internal";
          purge_cache = off;
      }

      server {
          label       = "DFINITY";
          ip          = 10.20.13.192;
          preset      = off;
          uptest      = ping;
          edns_query  = yes;
          lean_query  = yes;
          include     = ".dfinity.build";
          include     = ".dfinity.internal";
          exclude     = "vpn.dfinity.systems";
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
          include     = "vpn.dfinity.systems";
          exclude     = ".dfinity.build";
          exclude     = ".dfinity.internal";
          purge_cache = off;
      }

      # The servers provided by OpenDNS are fast, but they do not reply with
      # NXDOMAIN for non-existant domains, instead they supply you with an
      # address of one of their search engines. They also lie about the
      # addresses of the search engines of google, microsoft and yahoo. If you
      # do not like this behaviour the "reject" option may be useful.
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
          include     = "vpn.dfinity.systems";
          exclude     = ".dfinity.build";
          exclude     = ".dfinity.internal";
          purge_cache = off;
      }

      # This section is meant for resolving from root servers.
      server {
          label             = "root-servers";
          root_server       = discover;
          ip                = 198.41.0.4, 192.228.79.201;
          randomize_servers = on;
          exclude           = ".local";
          include           = "vpn.dfinity.systems";
          exclude           = ".dfinity.build";
          exclude           = ".dfinity.internal";
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
    package = pkgs.nixStable;

    useSandbox = false;
    sandboxPaths = [
      "/System/Library/Frameworks"
      "/System/Library/PrivateFrameworks"
      "/usr/lib"
      "/private/tmp"
      "/private/var/tmp"
      "/usr/bin/env"
    ];

    nixPath = [
      "darwin-config=$HOME/src/nix/config/darwin.nix"
      "home-manager=$HOME/src/nix/home-manager"
      "darwin=$HOME/src/nix/darwin"
      "nixpkgs=$HOME/src/nix/nixpkgs"
      "ssh-config-file=$HOME/.ssh/config"
      "ssh-auth-sock=$HOME/.config/gnupg/S.gpg-agent.ssh"
    ];

    trustedUsers = [ "johnw" "@admin" ];

    trustedBinaryCaches = [
    ];
    binaryCaches = [
    ];
    binaryCachePublicKeys = [
      "newartisans.com:RmQd/aZOinbJR/G5t+3CIhIxT5NBjlCRvTiSbny8fYw="
      "cache.dfinity.systems-1:IcOn/2SVyPGOi8i3hKhQOlyiSQotiOBKwTFmyPX5YNw="
      "hydra.dfinity.systems-2:KMTixHrh9DpAjF/0xU/49VEtNuGzQ71YaVIUSOLUaCM="
    ];

    extraOptions = ''
      secret-key-files = ${xdg_configHome}/gnupg/nix-signing-key.sec
    '';
  } //
  (if localconfig.hostname == "hermes" then {
     maxJobs = 8;
     buildCores = 4;
     distributedBuilds = false;

     buildMachines = [
       { hostName = "vulcan";
         sshUser = "johnw";
         sshKey = "${xdg_configHome}/ssh/id_local";
         system = "x86_64-darwin";
         maxJobs = 20;
         buildCores = 10;
         speedFactor = 4;
       }
       { hostName = "nix-docker";
         sshUser = "root";
         sshKey = "${xdg_configHome}/ssh/nix-docker_rsa";
         system = "x86_64-linux";
         maxJobs = 4;
         buildCores = 2;
         speedFactor = 3;
       }
       { hostName = "zrh-1";
         sshUser = "johnw";
         sshKey = "${xdg_configHome}/ssh/id_dfinity";
         system = "x86_64-linux";
         maxJobs = 8;
         buildCores = 4;
         speedFactor = 2;
       }
       { hostName = "hydra";
         sshUser = "ec2-user";
         sshKey = "${xdg_configHome}/ssh/id_dfinity";
         system = "x86_64-linux";
         maxJobs = 1;
         buildCores = 1;
         speedFactor = 1;
       }
     ];

     trustedBinaryCaches = [
       https://nix.dfinity.systems
     ];
     binaryCaches = [
       https://nix.dfinity.systems
     ];
   }
   else if localconfig.hostname == "fin" then {
     maxJobs = 8;
     buildCores = 4;
     distributedBuilds = true;

     buildMachines = [
       { hostName = "vulcan";
         sshUser = "johnw";
         sshKey = "${xdg_configHome}/ssh/id_local";
         system = "x86_64-darwin";
         maxJobs = 20;
         buildCores = 10;
         speedFactor = 4;
       }
       # { hostName = "hermes";
       #   sshUser = "johnw";
       #   sshKey = "${xdg_configHome}/ssh/id_local";
       #   system = "x86_64-darwin";
       #   maxJobs = 16;
       #   buildCores = 4;
       #   speedFactor = 2;
       # }
     ];
   }
   else if localconfig.hostname == "vulcan" then {
     maxJobs = 20;
     buildCores = 10;
     distributedBuilds = true;

     buildMachines = [
       { hostName = "nix-docker";
         sshUser = "root";
         sshKey = "${xdg_configHome}/ssh/nix-docker_rsa";
         system = "x86_64-linux";
         maxJobs = 4;
         buildCores = 2;
         speedFactor = 3;
       }
       { hostName = "zrh-1";
         sshUser = "johnw";
         sshKey = "${xdg_configHome}/ssh/id_dfinity";
         system = "x86_64-linux";
         maxJobs = 8;
         buildCores = 4;
         speedFactor = 2;
       }
       { hostName = "hydra";
         sshUser = "ec2-user";
         sshKey = "${xdg_configHome}/ssh/id_dfinity";
         system = "x86_64-linux";
         maxJobs = 1;
         buildCores = 1;
         speedFactor = 1;
       }
     ];

     trustedBinaryCaches = [
       https://nix.dfinity.systems
     ];
     binaryCaches = [
       https://nix.dfinity.systems
     ];
   }
   else {});

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
