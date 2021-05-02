{ pkgs, lib, config, ... }:

let home           = builtins.getEnv "HOME";
    tmpdir         = "/tmp";
    localconfig    = import <localconfig>;

    xdg_configHome = "${home}/.config";
    xdg_dataHome   = "${home}/.local/share";
    xdg_cacheHome  = "${home}/.cache";

in {
  imports = [ <home-manager/nix-darwin> ];

  services = {
    nix-daemon.enable = false;
    activate-system.enable = true;
  };

  programs = {
    zsh.enable = true;
  };

  users = {
    users.johnw = {
      name = "johnw";
      home = "/Users/johnw";
      shell = pkgs.zsh;
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    users.johnw = import ./home.nix;
  };

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowBroken = false;
      allowInsecure = false;
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

  nix = {
    package = pkgs.nixStable;
    useDaemon = false;

    nixPath = lib.mkForce [{
      nixpkgs         = "${home}/src/nix/nixpkgs";
      darwin          = "${home}/src/nix/darwin";
      darwin-config   = "${home}/src/nix/config/darwin.nix";
      home-manager    = "${home}/src/nix/home-manager";
      ssh-config-file = "${home}/.ssh/config";
      ssh-auth-sock   = "${xdg_configHome}/gnupg/S.gpg-agent.ssh";
    }];

    trustedUsers = [ "johnw" "@admin" ];

    extraOptions = ''
      secret-key-files = ${xdg_configHome}/gnupg/nix-signing-key.sec
    '';
  } //
  (let
     zrh-3 = {
       hostName = "zrh-3";
       sshUser = "johnw";
       sshKey = "${xdg_configHome}/ssh/id_dfinity";
       system = "x86_64-linux";
       maxJobs = 16;
       buildCores = 4;
       speedFactor = 4;
       supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
     };
     vulcan = {
       hostName = "vulcan";
       sshUser = "johnw";
       sshKey = "${xdg_configHome}/ssh/id_local";
       system = "x86_64-darwin";
       maxJobs = 10;
       buildCores = 2;
       speedFactor = 4;
     }; in
   if localconfig.hostname == "hermes" then rec {
     maxJobs = 8;
     buildCores = 2;
     distributedBuilds = true;

     buildMachines = [
       # vulcan
       zrh-3
     ];

     requireSignedBinaryCaches = false;
     binaryCaches = [
       # ssh://vulcan
     ];
   }
   else if localconfig.hostname == "vulcan" then rec {
     maxJobs = 10;
     buildCores = 2;
     distributedBuilds = true;

     buildMachines = [
       zrh-3
     ];

     binaryCaches = [
     ];
   }
   else {});

  system = {
    stateVersion = 4;

    defaults = {
      NSGlobalDomain = {
        AppleKeyboardUIMode = 3;
        ApplePressAndHoldEnabled = false;
      };
  
      dock = {
        autohide = true;
        launchanim = false;
        orientation = "right";
      };
  
      trackpad.Clicking = true;
    };
  };

  launchd = 
    let
      iterate = StartInterval: {
        inherit StartInterval;
        Nice = 5;
        LowPriorityIO = true;
        AbandonProcessGroup = true;
      }; 
      runCommand = command: {
        inherit command;
        serviceConfig.RunAtLoad = true;
        serviceConfig.KeepAlive = true;
      }; in {

    daemons = {
      cleanup = {
        script = ''
          export PYTHONPATH=$PYTHONPATH:${pkgs.dirscan}/libexec
          ${pkgs.python2}/bin/python ${pkgs.dirscan}/bin/cleanup -u \
              >> /var/log/cleanup.log 2>&1
        '';
        serviceConfig = iterate 86400;
      };
  
      limits = {
        script = ''
          /bin/launchctl limit maxfiles 524288 524288
          /bin/launchctl limit maxproc 8192 8192
        '';
        serviceConfig.RunAtLoad = true;
        serviceConfig.KeepAlive = false;
      };
    } //
    (if localconfig.hostname == "vulcan" then {
      snapshots = {
        script = ''
          export PATH=$PATH:${pkgs.my-scripts}/bin:/usr/local/bin
          date >> /var/log/snapshots.log 2>&1
          snapshots tank
        '';
        serviceConfig = iterate 2700;
      };
  
      tank = {
        command = "/usr/local/bin/zpool import tank";
        serviceConfig.RunAtLoad = true;
        serviceConfig.KeepAlive = false;
      };
     } else {});

    user.agents = {
      aria2c = runCommand 
        ("${pkgs.aria2}/bin/aria2c "
          + "--enable-rpc "
          + "--dir ${home}/Downloads "
          + "--check-integrity "
          + "--continue ");
  
      dovecot = {
        command = "${pkgs.dovecot}/libexec/dovecot/imap -c /etc/dovecot/dovecot.conf";
        serviceConfig = {
          WorkingDirectory = "${pkgs.dovecot}/lib";
          inetdCompatibility.Wait = "nowait";
          Sockets.Listeners = {
            SockNodeName = "127.0.0.1";
            SockServiceName = "9143";
          };
        };
      };
  
      locate = {
        script = ''
          export PATH=${pkgs.findutils}/bin:$PATH
          export HOME=${home}
          if [[ ! -d ${xdg_dataHome}/locate ]]; then
              mkdir ${xdg_dataHome}/locate
          fi
          date >> ${xdg_dataHome}/locate/locate.log 2>&1
          ${pkgs.my-scripts}/bin/update.locate \
              >> ${xdg_dataHome}/locate/locate.log 2>&1
        '';
        serviceConfig = iterate 86400;
      };
  
      # rdm = rec {
      #   script = ''
      #     ${pkgs.rtags}/bin/rdm \
      #         --verbose \
      #         --launchd \
      #         --inactivity-timeout 300 \
      #         --socket-file ${serviceConfig.Sockets.Listeners.SockPathName}
      #         --log-file ${xdg_dataHome}/rdm/rtags.launchd.log
      #   '';
      #   serviceConfig.Sockets.Listeners.SockPathName
      #     = "${xdg_cacheHome}/rdm/socket";
      # };
    } //
    (if localconfig.hostname == "vulcan" then {
       znc = runCommand "${pkgs.znc}/bin/znc -f -d ${xdg_configHome}/znc";
     } else {});
  };

  environment = {
    etc."dovecot/modules".source = "${home}/.nix-profile/lib/dovecot";
    etc."dovecot/dovecot.conf".text = ''
      base_dir = ${home}/Library/Application Support/dovecot
      default_login_user = johnw
      default_internal_user = johnw
      auth_mechanisms = plain
      disable_plaintext_auth = no
      lda_mailbox_autocreate = yes
      log_path = syslog
      mail_gid = 20
      mail_location = mdbox:${home}/Messages/Mailboxes
      login_plugin_dir = ${home}/.nix-profile/lib/dovecot
      mail_plugin_dir = ${home}/.nix-profile/lib/dovecot
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

      service auth {
        unix_listener auth-userdb {
          mode = 0644
          user = johnw
          group = johnw
        }
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
  };
}
