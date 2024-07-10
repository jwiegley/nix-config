{ pkgs, lib, config, hostname, inputs, ... }:

let home           = builtins.getEnv "HOME";
    tmpdir         = "/tmp";

    xdg_configHome = "${home}/.config";
    xdg_dataHome   = "${home}/.local/share";
    xdg_cacheHome  = "${home}/.cache";

in {
  services = {
    nix-daemon.enable = false;
    activate-system.enable = true;
  };

  users = {
    users.johnw = {
      name = "johnw";
      home = "/Users/johnw";
      shell = pkgs.zsh;

      openssh.authorizedKeys = {
        keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAING2r8bns7h9vZIfZSGsX+YmTSe2Tv1X8f/Qlqo+RGBb yubikey-gnupg"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJD0sIKWWVF+zIWcNm/BfsbCQxuUBHD8nRNSpZV+mCf+ ShellFish@iPhone-28062024"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIZQeQ/gKkOwuwktwD4z0ZZ8tpxNej3qcHS5ZghRcdAd ShellFish@iPad-22062024"
        ];
        keyFiles =
          if hostname == "vulcan" then [
            "${home}/${hostname}/id_athena.pub"
            "${home}/${hostname}/id_iphone.pub"
          ]
          else if hostname == "athena" then [
            "${home}/${hostname}/id_vulcan.pub"
            "${home}/${hostname}/id_iphone.pub"
          ]
          else if hostname == "hermes" then [
            "${home}/${hostname}/id_vulcan.pub"
            "${home}/${hostname}/id_athena.pub"
          ]
          else [];
      };
    };
  };

  fonts.packages = with pkgs; [
    dejavu_fonts
    scheherazade-new
    ia-writer-duospace
  ];

  programs = {
    zsh = {
      enable = true;
      enableCompletion = false;
    };
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
    };

    taps = [
      "kadena-io/pact"
    ];
    brews = [
      "openssl"
      "kadena-io/pact/pact"
      "z3"
    ];

    casks = [
      "docker"
      "drivedx"
      { name = "firefox"; greedy = true; }
      "hazel"
      "iterm2"
      "keyboard-maestro"
      "launchbar"
      "ollama"
      "vmware-fusion"
      "wireshark"
    ] ++ lib.optionals (hostname != "athena") [
      "1password"
      "1password-cli"
      "anki"
      # { name = "arc"; greedy = true; }
      "asana"
      "audacity"
      { name = "brave-browser"; greedy = true; }
      "carbon-copy-cloner"
      "choosy"
      # "datagraph"                 # Use DataGraph in App Store
      "dbvisualizer"
      "devonagent"
      "devonthink"
      "discord"
      "dungeon-crawl-stone-soup-tiles"
      "element"
      # "emacsclient"               # Not available
      "expandrive"
      "fantastical"
      "grammarly-desktop"
      "gpg-suite-no-mail"
      "lectrote"
      # "macwhisper"                # Use Whisper Transcription in AppStore
      # "marked"                    # Use Marked 2 in AppStore
      "mellel"
      "netdownloadhelpercoapp"
      "notion"
      # "omnigraffle"               # Stay at version 6
      { name = "opera"; greedy = true; }
      "pdf-expert"
      "sage"
      # "screenflow"                # Stay at version 9
      "signal"
      "slack"
      # "soulver"                   # Use Soulver 3 in App Store
      "soulver-cli"
      "spamsieve"
      "steam"
      "suspicious-package"
      "tagspaces"
      "telegram"
      "thinkorswim"
      "tor-browser"
      "ukelele"
      "unicodechecker"
      "vagrant"
      "vagrant-manager"
      "vagrant-vmware-utility"
      "virtual-ii"
      "visual-studio-code"
      { name = "vivaldi"; greedy = true; }
      "vlc"
      "whatsapp"
      "xnviewmp"
      "yubico-yubikey-manager"
      { name = "zoom"; greedy = true; }
      "zotero"
      "zulip"
    ] ++ lib.optionals (hostname == "athena") [
      "openzfs"
    ] ++ lib.optionals (hostname == "hermes") [
      "chronoagent"
    ] ++ lib.optionals (hostname == "vulcan") [
      "fujitsu-scansnap-home"
      "geektool"
      "gzdoom"
      "ledger-live"
      "raspberry-pi-imager"
      "chronosync"
    ];

    ## The following software, or versions of software, are not available
    ## via Homebrew or the App Store:

    # "Bookmap"
    # "Digital Photo Professional"
    # "EOS Utilityl"
    # "Kadena Chainweaver"
    # "MotiveWave"
    # "ScanSnap Online Update"
    # "ABBYY FineReader for ScanSnap"

    masApps = (if hostname != "athena" then {
      "1Password for Safari"  = 1569813296;
      "Bible Study"           = 472790630;
      "DataGraph"             = 407412840;
      "Drafts"                = 1435957248;
      "Grammarly for Safari"  = 1462114288;
      "Infuse"                = 1136220934;
      "Just Press Record"     = 1033342465;
      "Keynote"               = 409183694;
      "Kindle"                = 302584613;
      "Marked 2"              = 890031187;
      "Microsoft Excel"       = 462058435;
      "Microsoft PowerPoint"  = 462062816;
      "Microsoft Word"        = 462054704;
      "Ninox Database"        = 901110441;
      "Notability"            = 360593530;
      "Parcel"                = 639968404;
      "Pixelmator Pro"        = 1289583905;
      "Prime Video"           = 545519333;
      "Shell Fish"            = 1336634154;
      "Soulver 3"             = 1508732804;
      "Whisper Transcription" = 1668083311;
      "WireGuard"             = 1451685025;
    } else {}) // {
      "Speedtest"             = 1153157709;
      "Xcode"                 = 497799835;
    };
  };

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowBroken = false;
      allowInsecure = false;
      allowUnsupportedSystem = false;

      permittedInsecurePackages = [
        "python-2.7.18.7"
        "libressl-3.4.3"
      ];
    };

    overlays =
      let path = ../overlays; in with builtins;
      map (n: import (path + ("/" + n)))
          (filter (n: match ".*\\.nix" n != null ||
                      pathExists (path + ("/" + n + "/default.nix")))
                  (attrNames (readDir path)))
        ++ [ (import ./envs.nix) ];
  };

  nix =
    let
      vulcan = {
        hostName = "vulcan";
        sshUser = "johnw";
        system = "x86_64-darwin";
        maxJobs = 10;
        buildCores = 2;
        speedFactor = 4;
      }; in {

    # package = pkgs.nixStable;
    useDaemon = true;

    # This entry lets us to define a system registry entry so that
    # `nixpkgs#foo` will use the nixpkgs that nix-darwin was last built with,
    # rather than whatever is the current unstable version.
    #
    # See https://yusef.napora.org/blog/pinning-nixpkgs-flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    nixPath = lib.mkForce (
         lib.mapAttrsToList (key: value: "${key}=${value.to.path}")
                            config.nix.registry
      ++ [{ ssh-config-file = "${home}/.ssh/config";
            ssh-auth-sock   = "${xdg_configHome}/gnupg/S.gpg-agent.ssh";
            darwin-config   = "${home}/src/nix/config/darwin.nix";
            hm-config       = "${home}/src/nix/config/home.nix";
          }]);

    settings = {
      trusted-users = [ "johnw" "@admin" ];
      max-jobs = 8;
      cores = 2;

      substituters = [
        # "https://cache.iog.io"
      ] ++ lib.optionals (hostname == "vulcan") [];

      trusted-substituters = [
      ] ++ lib.optionals (hostname == "vulcan") [];

      trusted-public-keys = [
        "newartisans.com:RmQd/aZOinbJR/G5t+3CIhIxT5NBjlCRvTiSbny8fYw="
        "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      ];
    };

    distributedBuilds = false;

    # buildMachines = lib.optionals (hostname == "hermes") [
    #   vulcan
    # ];

    extraOptions = ''
      gc-keep-derivations = true
      gc-keep-outputs = true
      secret-key-files = ${xdg_configHome}/gnupg/nix-signing-key.sec
      experimental-features = nix-command flakes
    '';
  };

  system = {
    stateVersion = 4;

    # activationScripts are executed every time you boot the system or run
    # `nixos-rebuild` / `darwin-rebuild`.
    activationScripts.postUserActivation.text = ''
      # activateSettings -u will reload the settings from the database and
      # apply them to the current session, so we do not need to logout and
      # login again to make the changes take effect.
      /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    '';

    defaults = {
      NSGlobalDomain = {
        AppleKeyboardUIMode = 3;
        AppleInterfaceStyle = "Dark";
        AppleShowAllExtensions = true;
        NSAutomaticWindowAnimationsEnabled = false;
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;
        "com.apple.keyboard.fnState" = true;
        _HIHideMenuBar = true;
        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.sound.beep.volume" = 0.0;
        "com.apple.sound.beep.feedback" = 0;
        ApplePressAndHoldEnabled = false;
      };

      CustomUserPreferences = {
        "com.apple.finder" = {
          ShowExternalHardDrivesOnDesktop = false;
          ShowHardDrivesOnDesktop = false;
          ShowMountedServersOnDesktop = true;
          ShowRemovableMediaOnDesktop = true;
          _FXSortFoldersFirst = true;
          # When performing a search, search the current folder by default
          FXDefaultSearchScope = "SCcf";
        };

        "com.apple.desktopservices" = {
          # Avoid creating .DS_Store files on network or USB volumes
          DSDontWriteNetworkStores = true;
          DSDontWriteUSBStores = true;
        };

        "com.apple.spaces" = {
          "spans-displays" = 0; # Display have seperate spaces
        };

        "com.apple.WindowManager" = {
          EnableStandardClickToShowDesktop = 0; # Click wallpaper to reveal desktop
          StandardHideDesktopIcons = 0; # Show items on desktop
          HideDesktop = 0; # Do not hide items on desktop & stage manager
          StageManagerHideWidgets = 0;
          StandardHideWidgets = 0;
        };

        "com.apple.screencapture" = {
          location = "~/Downloads";
          type = "png";
        };

        "com.apple.AdLib" = {
          allowApplePersonalizedAdvertising = false;
        };

        # Prevent Photos from opening automatically when devices are plugged in
        "com.apple.ImageCapture".disableHotPlug = true;

        "com.apple.print.PrintingPrefs" = {
          # Automatically quit printer app once the print jobs complete
          "Quit When Finished" = true;
        };

        "com.apple.SoftwareUpdate" = {
          AutomaticCheckEnabled = true;
          # Check for software updates daily, not just once per week
          ScheduleFrequency = 1;
          # Download newly available updates in background
          AutomaticDownload = 1;
          # Install System data files & security updates
          CriticalUpdateInstall = 1;
        };
        "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;

        # Turn on app auto-update
        "com.apple.commerce".AutoUpdate = true;
      };

      ".GlobalPreferences" = {
        "com.apple.sound.beep.sound" = "/System/Library/Sounds/Funk.aiff";
      };

      dock = {
        autohide = true;
        orientation = "right";
        launchanim = false;
        show-process-indicators = true;
        show-recents = false;
        static-only = true;
      };

      finder = {
        AppleShowAllExtensions = true;
        ShowPathbar = true;
        FXEnableExtensionChangeWarning = false;
      };

      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };
    };

    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = true;
    };
  };

  # networking = if hostname == "vulcan" then {
  #   dns = [ "192.168.50.1" ];
  #   search = [ "local" ];
  #   knownNetworkServices = [ "Ethernet" "Thunderbolt Bridge" ];
  # } else {};

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
      # cleanup = {
      #   script = ''
      #     export PYTHONPATH=$PYTHONPATH:${pkgs.dirscan}/libexec
      #     ${pkgs.python3}/bin/python ${pkgs.dirscan}/bin/cleanup -u \
      #         >> /var/log/cleanup.log 2>&1
      #   '';
      #   serviceConfig = iterate 86400;
      # };

      limits = {
        script = ''
          /bin/launchctl limit maxfiles 524288 524288
          /bin/launchctl limit maxproc 8192 8192
        '';
        serviceConfig.RunAtLoad = true;
        serviceConfig.KeepAlive = false;
      };

      # pdnsd = {
      #   script = ''
      #     cp -pL /etc/pdnsd.conf ${tmpdir}/.pdnsd.conf
      #     chmod 700 ${tmpdir}/.pdnsd.conf
      #     chown root ${tmpdir}/.pdnsd.conf
      #     touch ${xdg_cacheHome}/pdnsd/pdnsd.cache
      #     ${pkgs.pdnsd}/sbin/pdnsd -c ${tmpdir}/.pdnsd.conf
      #   '';
      #   serviceConfig.RunAtLoad = true;
      #   serviceConfig.KeepAlive = true;
      # };
    }
    // lib.optionalAttrs (hostname == "vulcan") {
      unmount = {
        script = ''
          diskutil unmount /Volumes/BOOTCAMP
          diskutil unmount /Volumes/Games
        '';
        serviceConfig.RunAtLoad = true;
        serviceConfig.KeepAlive = false;
      };

      zfs-import = {
        script = ''
          # export PATH=/usr/local/zfs/bin:$PATH
          # export DYLD_LIBRARY_PATH=/usr/local/zfs/lib:$DYLD_LIBRARY_PATH
          # zpool import -d /var/run/disk/by-serial -a
          kextunload /Library/Extensions/zfs.kext
        '';
        serviceConfig.RunAtLoad = true;
        serviceConfig.KeepAlive = false;
      };
     }
    // lib.optionalAttrs (hostname == "athena") {
      snapshots = {
        script = ''
          date >> /var/log/snapshots.log 2>&1
          ${pkgs.sanoid}/bin/sanoid --cron --force-prune --verbose \
              >> /var/log/snapshots.log 2>&1
        '';
        serviceConfig = iterate 3600;
      };

      # workspace-update = {
      #   script = ''
      #     date >> /var/log/workspace-update.log 2>&1
      #     export PATH=${pkgs.git}/bin:${pkgs.gitAndTools.git-workspace}/bin:$PATH
      #     unset GITHUB_TOKEN
      #     ${pkgs.my-scripts}/bin/workspace-update \
      #         --passwords /Users/johnw/athena/restic-passwords 2>&1 \
      #         >> /var/log/workspace-update.log 2>&1
      #   '';
      #   serviceConfig = {
      #     StartCalendarInterval = [
      #       {
      #         Hour = 1;
      #         Minute = 30;
      #       }
      #     ];
      #     Nice = 5;
      #     LowPriorityIO = true;
      #     AbandonProcessGroup = true;
      #   };
      # };

      b2-restic = {
        script = ''
          date >> /var/log/b2-restic.log 2>&1
          export PATH=${pkgs.restic}/bin:/usr/local/zfs/bin:$PATH
          export DYLD_LIBRARY_PATH=/usr/local/zfs/lib:$DYLD_LIBRARY_PATH
          unset RESTIC_PASSWORD_COMMAND
          export HOME=/Users/johnw
          ${pkgs.my-scripts}/bin/b2-restic \
              --passwords /Users/johnw/athena/restic-passwords tank --all 2>&1 \
              | grep --line-buffered -v "can not obtain extended attribute" \
              >> /var/log/b2-restic.log 2>&1
        '';
        serviceConfig = {
          StartCalendarInterval = [
            {
              Hour = 2;
              Minute = 30;
            }
          ];
          Nice = 5;
          LowPriorityIO = true;
          AbandonProcessGroup = true;
        };
      };

      zfs-import = {
        script = ''
          export PATH=/usr/local/zfs/bin:$PATH
          export DYLD_LIBRARY_PATH=/usr/local/zfs/lib:$DYLD_LIBRARY_PATH
          zpool import -d /var/run/disk/by-serial -a
        '';
        serviceConfig.RunAtLoad = true;
        serviceConfig.KeepAlive = false;
      };
     };

    user.agents = {
      aria2c = runCommand
        ("${pkgs.aria2}/bin/aria2c "
          + "--enable-rpc "
          + "--dir ${home}/Downloads "
          + "--check-integrity "
          + "--continue ");
    };
  };

  environment.etc = lib.optionalAttrs (hostname == "athena") {
    "sanoid/sanoid.conf".text = ''
      [tank]

      use_template = archival
      recursive = yes
      process_children_only = yes

      [template_archival]

      frequently = 0
      hourly = 96
      daily = 90
      weekly = 26
      monthly = 12
      yearly = 30

      autoprune = yes

      [tank/ChainState/kadena]

      use_template = production
      recursive = yes
      process_children_only = yes

      [template_production]

      frequently = 0
      hourly = 24
      daily = 14
      weekly = 4
      monthly = 3
      yearly = 0

      autoprune = yes
    '';
  };
}
