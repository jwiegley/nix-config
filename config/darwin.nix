{ pkgs, lib, config, hostname, inputs, ... }:

let home           = builtins.getEnv "HOME";
    tmpdir         = "/tmp";

    xdg_configHome = "${home}/.config";
    xdg_dataHome   = "${home}/.local/share";
    xdg_cacheHome  = "${home}/.cache";

in {
  users = {
    users.johnw = {
      name = "johnw";
      inherit home;
      shell = pkgs.zsh;

      openssh.authorizedKeys = {
        keys = [
          # GnuPG auth key stored on Yubikeys
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJAj2IzkXyXEl+ReCg9H+t55oa6GIiumPWeufcYCWy3F yubikey-gnupg"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAING2r8bns7h9vZIfZSGsX+YmTSe2Tv1X8f/Qlqo+RGBb yubikey-14476831-gnupg"
          # ShellFish iPhone key
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJD0sIKWWVF+zIWcNm/BfsbCQxuUBHD8nRNSpZV+mCf+ ShellFish@iPhone-28062024"
          # ShellFish iPad key
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIZQeQ/gKkOwuwktwD4z0ZZ8tpxNej3qcHS5ZghRcdAd ShellFish@iPad-22062024"
        ];
        keyFiles =
          # Each machine accepts SSH key authentication from the rest
          import ./key-files.nix { inherit (pkgs) lib; }
            [ "hera" "clio" "athena" "vulcan" ] home hostname;
      };
    };
  };

  fonts.packages = with pkgs; [
    dejavu_fonts
    nerd-fonts.dejavu-sans-mono
    scheherazade-new
    ia-writer-duospace
  ];

  programs = {
    zsh = {
      enable = true;
      enableCompletion = false;
    };
  };

  # services = {
  #   postgresql = {
  #     enable = true;
  #     package = pkgs.postgresql.withPackages (p: with p; [ pgvector ]);
  #     dataDir = "${home}/Databases/postgresql";
  #   };
  # };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "zap";
    };

    taps = [
      # "kadena-io/pact"
      "beeftornado/rmtree"
    ];
    brews = [
      "ykman"
      "node@22"
      # Brews for Kadena
      # "kadena-io/pact/pact"
      "openssl"
      "z3"
    ];

    casks = [
      "carbon-copy-cloner"
      "docker"
      "drivedx"
      # "hazel"                   # Stay at version 5
      "iterm2"
      "vmware-fusion"
      # "vagrant"
      # "vagrant-manager"
      # "vagrant-vmware-utility"
      "wireshark"
    ] ++ lib.optionals (hostname == "vulcan" || hostname == "hera") [
      "fujitsu-scansnap-home"
      "gzdoom"
      "raspberry-pi-imager"
      "chronoagent"
    ] ++ lib.optionals (pkgs.system == "aarch64-darwin") [
      "lm-studio"
      "diffusionbee"
    ] ++ lib.optionals (hostname == "clio") [
      "aldente"
      "chronosync"
    ] ++ lib.optionals (hostname == "athena") [
      "openzfs"
    ] ++ lib.optionals (hostname != "athena") [
      "1password"
      "1password-cli"
      "affinity-photo"
      "anki"
      { name = "arc"; greedy = true; }
      "asana"
      "audacity"
      { name = "brave-browser"; greedy = true; }
      "choosy"
      # "datagraph"                 # Use DataGraph in App Store
      "dbvisualizer"
      "devonagent"
      # "devonthink"
      "discord"
      "duckduckgo"
      "dungeon-crawl-stone-soup-tiles"
      "element"
      "expandrive"
      "fantastical"
      { name = "firefox"; greedy = true; }
      "geektool"
      "grammarly-desktop"
      # "gpg-suite-no-mail"
      "keyboard-maestro"
      "launchbar"
      "lectrote"
      "ledger-live"
      # "macwhisper"                # Use Whisper Transcription in App Store
      # "marked"                    # Use Marked 2 in App Store
      "mellel"
      "netdownloadhelpercoapp"
      "notion"
      # "omnigraffle"               # Stay at version 6
      { name = "opera"; greedy = true; }
      { name = "opera"; greedy = true; }
      "pdf-expert"
      # "screenflow"                # Stay at version 9
      "signal"
      "slack"
      # "soulver"                   # Use Soulver 3 in App Store
      "soulver-cli"
      "spamsieve"
      "steam"
      "suspicious-package"
      "telegram"
      "thinkorswim"
      "tor-browser"
      "ukelele"
      "unicodechecker"
      "virtual-ii"
      { name = "vivaldi"; greedy = true; }
      "vlc"
      "whatsapp"
      "xnviewmp"
      { name = "zoom"; greedy = true; }
      "zotero"
      "zulip"
    ];

    ## The following software, or versions of software, are not available
    ## via Homebrew or the App Store:

    # "Bookmap"
    # "Digital Photo Professional"
    # "EOS Utility"
    # "Kadena Chainweaver"
    # "MotiveWave"
    # "ScanSnap Online Update"
    # "ABBYY FineReader for ScanSnap"

    ## jww (2025-04-03): These keep getting re-installed
    # masApps = {
    #   "Speedtest"             = 1153157709;
    #   "Xcode"                 = 497799835;
    # } // lib.optionalAttrs (hostname != "athena") {
    #   "1Password for Safari"  = 1569813296;
    #   "Bible Study"           = 472790630;
    #   "DataGraph"             = 407412840;
    #   "Drafts"                = 1435957248;
    #   "Grammarly for Safari"  = 1462114288;
    #   "Infuse"                = 1136220934;
    #   "Just Press Record"     = 1033342465;
    #   "Keynote"               = 409183694;
    #   "Kindle"                = 302584613;
    #   "Marked 2"              = 890031187;
    #   "Microsoft Excel"       = 462058435;
    #   "Microsoft PowerPoint"  = 462062816;
    #   "Microsoft Word"        = 462054704;
    #   "Ninox Database"        = 901110441;
    #   "Notability"            = 360593530;
    #   "Paletter"              = 1494948845;
    #   "Perplexity"            = ;
    #   "Pixelmator Pro"        = 1289583905;
    #   "Prime Video"           = 545519333;
    #   "Shell Fish"            = 1336634154;
    #   "Soulver 3"             = 1508732804;
    #   "Whisper Transcription" = 1668083311;
    #   "WireGuard"             = 1451685025;
    #   "iMovie"                = 408981434;
    # };
  };

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowBroken = false;
      allowInsecure = false;
      allowUnsupportedSystem = false;

      permittedInsecurePackages = [
        "emacs-mac-macport-with-packages-29.4"
        "emacs-mac-macport-29.4"
        "emacs-29.4"
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
        ++ [ (import ./envs.nix) 
             inputs.nurpkgs.overlays.default
           ];
  };

  nix =
    let
      hera = {
        hostName = "hera";
        protocol = "ssh-ng";
        system = "aarch64-darwin";
        sshUser = "johnw";
        maxJobs = 24;
        speedFactor = 4;
      };

      athena = {
        hostName = "athena";
        protocol = "ssh-ng";
        system = "aarch64-darwin";
        sshUser = "johnw";
        maxJobs = 10;
        speedFactor = 2;
      };
    in {

    package = pkgs.nix;

    # This entry lets us to define a system registry entry so that
    # `nixpkgs#foo` will use the nixpkgs that nix-darwin was last built with,
    # rather than whatever is the current unstable version.
    #
    # See https://yusef.napora.org/blog/pinning-nixpkgs-flake
    # registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    nixPath = lib.mkForce (
         lib.mapAttrsToList (key: value: "${key}=${value.to.path}")
                            config.nix.registry
      ++ [{ ssh-config-file = "${home}/.ssh/config";
            ssh-auth-sock   = "${xdg_configHome}/gnupg/S.gpg-agent.ssh";
            darwin-config   = "${home}/src/nix/config/darwin.nix";
            hm-config       = "${home}/src/nix/config/home.nix";
          }]);

    settings = {
      trusted-users = [ "@admin" "@builders" "johnw" ];
      max-jobs = if (hostname == "clio") then 10 else 24;
      cores = 2;

      substituters = [
        # "https://cache.iog.io"
      ];
      trusted-substituters = [
      ];
      trusted-public-keys = [
        "newartisans.com:RmQd/aZOinbJR/G5t+3CIhIxT5NBjlCRvTiSbny8fYw="
        "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      ];
    };

    distributedBuilds = true;
    buildMachines =
      if hostname == "clio"
      then [ hera athena ]
      else if hostname == "athena"
           then [ hera ]
           else [];

    extraOptions = ''
      gc-keep-derivations = true
      gc-keep-outputs = true
      secret-key-files = ${xdg_configHome}/gnupg/nix-signing-key.sec
      experimental-features = nix-command flakes
    '';
    };

  ids.gids.nixbld = 
    if (hostname == "vulcan" || hostname == "athena") then 30000 else 350;

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
        _HIHideMenuBar = hostname == "vulcan" || hostname == "hera" || hostname == "athena";
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

  # networking = lib.optionalAttrs (hostname == "hera") {
  #   dns = [ "192.168.50.1" ];
  #   search = [ "local" ];
  #   knownNetworkServices = [ "Ethernet" "Thunderbolt Bridge" ];
  # };

  launchd =
    let
      iterate = StartInterval: {
        inherit StartInterval;
        Nice = 5;
        LowPriorityIO = true;
        AbandonProcessGroup = true;
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
    // lib.optionalAttrs (hostname == "hera") {
      "sysctl-vram-limit" = {
        script = ''
          # This leaves 64 GB of working memory remaining
          # /usr/sbin/sysctl iogpu.wired_limit_mb=458752

          # This leaves 32 GB of working memory remaining, and is best for
          # when the machine will only be used headless as a server from
          # remote, during longer trips.
          /usr/sbin/sysctl iogpu.wired_limit_mb=491520
        '';
        serviceConfig.RunAtLoad = true;
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
              Hour = 3;
              Minute = 0;
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

    user = {
      agents = {
        aria2c = {
          script = ''
            ${pkgs.aria2}/bin/aria2c    \
                --enable-rpc            \
                --dir ${home}/Downloads \
                --check-integrity       \
                --continue
          '';
          serviceConfig.RunAtLoad = true;
          serviceConfig.KeepAlive = true;
        };
      } // lib.optionalAttrs (hostname == "hera") {
        ollama = {
          script = ''
            export OLLAMA_HOST=0.0.0.0:11434
            export OLLAMA_KEEP_ALIVE=${if hostname == "clio" then "5m" else "60m"}
            export OLLAMA_NOHISTORY=true
            ${pkgs.ollama}/bin/ollama serve
          '';
          serviceConfig.RunAtLoad = true;
          serviceConfig.KeepAlive = true;
        };
      } // lib.optionalAttrs (hostname == "hera") {
        lmstudio = {
          script = ''
            ${xdg_dataHome}/lmstudio/bin/lms server start
          '';
          serviceConfig.RunAtLoad = true;
          serviceConfig.KeepAlive = true;
        };
      };
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
