{ pkgs, lib, config, hostname, inputs, overlays, ... }:

let home           = "/Users/johnw";
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
            [ "hera" "clio" "athena" ] home hostname;
      };
    };
  };

  fonts.packages = with pkgs; [
    dejavu_fonts
    nerd-fonts.dejavu-sans-mono
    scheherazade-new
    ia-writer-duospace
    liberation_ttf
  ];

  programs = {
    zsh = {
      enable = true;
      enableCompletion = false;
    };

    gnupg.agent = {
      enable = true;
      enableSSHSupport = false;
    };
  };

  services = lib.optionalAttrs (hostname == "clio" || hostname == "hera") {
    postgresql = {
      enable = false;
      package = pkgs.postgresql.withPackages (p: with p; [ pgvector ]);
      dataDir = "${home}/${hostname}/postgresql";
      authentication = ''
        local all all              trust
        host  all all localhost    trust
        host  all all 127.0.0.1/32 trust
      '';
    };
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "zap";
    };

    taps = [
      "kadena-io/pact"
    ];
    brews = [
      "ykman"
      "nss"

      # Brews for Kadena
      "kadena-io/pact/pact"
      "openssl"
      "z3"

      "llm"
    ];

    casks = [
      "carbon-copy-cloner"
      "docker"
      "drivedx"
      "iterm2"
      "vmware-fusion"
      # "vagrant"
      # "vagrant-manager"
      # "vagrant-vmware-utility"
      "wireshark"
    ] ++ lib.optionals (pkgs.system == "aarch64-darwin") [
      # "lm-studio"
      "diffusionbee"
    ] ++ lib.optionals (hostname == "hera") [
      "fujitsu-scansnap-home"
      "gzdoom"
      "raspberry-pi-imager"
    ] ++ lib.optionals (hostname == "clio") [
      "aldente"
    ] ++ lib.optionals (hostname != "athena") [
      "1password"
      "1password-cli"
      "affinity-photo"
      "anki"
      # { name = "arc"; greedy = true; }
      "asana"
      "audacity"
      { name = "brave-browser"; greedy = true; }
      "choosy"
      "corelocationcli"
      # "datagraph"                 # Use DataGraph in App Store
      "dbvisualizer"
      "devonagent"
      "devonthink"
      { name = "thebrowsercompany-dia"; greedy = true; }
      "discord"
      { name = "duckduckgo"; greedy = true; }
      "dungeon-crawl-stone-soup-tiles"
      "element"
      "expandrive"
      "fantastical"
      { name = "firefox"; greedy = true; }
      "geektool"
      "grammarly-desktop"
      "key-codes"
      "keyboard-maestro"
      "launchbar"
      "lectrote"
      "ledger-live"
      # "macwhisper"                # Use Whisper Transcription in App Store
      # "marked"                    # Use Marked 2 in App Store
      "mellel"
      "netdownloadhelpercoapp"
      # "notion"
      # "omnigraffle"               # Stay at version 6
      { name = "opera"; greedy = true; }
      "pdf-expert"
      # "screenflow"                # Stay at version 9
      "signal"
      "slack"
      # "soulver"                   # Use Soulver 3 in App Store
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
      # "zulip"
    ];

    ## The following software, or versions of software, are not available
    ## via Homebrew or the App Store:

    # "Bookmap"
    # "Digital Photo Professional"
    # "EOS Utility"
    # "Kadena Chainweaver"
    # "MotiveWave"
    # "ScanSnap Online Update"
    # "Photo Supreme"
    # "ABBYY FineReader for ScanSnap"

    masApps = lib.optionalAttrs (hostname != "athena") {
      "1Password for Safari"  = 1569813296;
      "Bible Study"           = 472790630;
      "DataGraph"             = 407412840;
      "Drafts"                = 1435957248;
      "Grammarly for Safari"  = 1462114288;
      "Just Press Record"     = 1033342465;
      "Keynote"               = 409183694;
      "Kindle"                = 302584613;
      "Marked 2"              = 890031187;
      "Microsoft Excel"       = 462058435;
      "Microsoft PowerPoint"  = 462062816;
      "Microsoft Word"        = 462054704;
      "Ninox Database"        = 901110441;
      "Notability"            = 360593530;
      "Paletter"              = 1494948845;
      "Pixelmator Pro"        = 1289583905;
      "Prime Video"           = 545519333;
      "Shell Fish"            = 1336634154;
      "Soulver 3"             = 1508732804;
      "Speedtest"             = 1153157709;
      "Whisper Transcription" = 1668083311;
      "WireGuard"             = 1451685025;
      "Xcode"                 = 497799835;
      "iMovie"                = 408981434;
    };
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

    overlays = overlays
      ++ (let path = ../overlays; in with builtins;
            map (n: import (path + ("/" + n)))
                (filter (n: match ".*\\.nix" n != null ||
                            pathExists (path + ("/" + n + "/default.nix")))
                        (attrNames (readDir path))));
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
            darwin-config   = "${home}/src/nix/config/darwin.nix";
            hm-config       = "${home}/src/nix/config/home.nix";
          }]);

    settings = {
      trusted-users = [ "@admin" "@builders" "johnw" ];
      max-jobs = if (hostname == "clio") then 4 else 8;
      cores = 10;

      substituters = [
      ];
      trusted-substituters = [
      ];
      trusted-public-keys = [
        "newartisans.com:RmQd/aZOinbJR/G5t+3CIhIxT5NBjlCRvTiSbny8fYw="
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

  ids.gids.nixbld = if hostname == "athena" then 30000 else 350;

  system = {
    stateVersion = 4;

    primaryUser = "johnw";

    defaults = {
      NSGlobalDomain = {
        AppleKeyboardUIMode = 3;
        AppleInterfaceStyle = "Dark";
        AppleShowAllExtensions = true;
        NSAutomaticWindowAnimationsEnabled = false;
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;
        "com.apple.keyboard.fnState" = true;
        _HIHideMenuBar = hostname != "clio";
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

  launchd = {
    daemons = {
      limits = {
        script = ''
          /bin/launchctl limit maxfiles 524288 524288
          /bin/launchctl limit maxproc 8192 8192
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

        llama-swap =
          let ip-address = if hostname == "clio"
                           then "192.168.50.112"
                           else if hostname == "athena"
                                then "192.168.50.235"
                                else if hostname == "hera"
                                     then "192.168.50.5"
                                     else "127.0.0.1";
          in {
            script = ''
              ${pkgs.llama-swap}/bin/llama-swap       \
              --listen "${ip-address}:8080"           \
              --config ${home}/Models/llama-swap.yaml
            '';
            serviceConfig.RunAtLoad = true;
            serviceConfig.KeepAlive = true;
          };

        llama-swap-https-proxy =
          let
            logDir = "${xdg_cacheHome}/llama-swap-proxy";
            config = pkgs.writeText "nginx.conf" ''
              worker_processes 1;
              pid ${logDir}/nginx.pid;
              error_log ${logDir}/error.log warn;
              events {
                worker_connections 1024;
              }
              http {
                server {
                  listen 8443 ssl;

                  ssl_certificate /Users/johnw/hera/hera.local+4.pem;
                  ssl_certificate_key /Users/johnw/hera/hera.local+4-key.pem;
                  ssl_protocols TLSv1.2 TLSv1.3;
                  ssl_prefer_server_ciphers on;
                  ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
                  
                  access_log ${logDir}/access.log;

                  location / {
                    proxy_pass http://localhost:8080;

                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;

                    proxy_connect_timeout 600;
                    proxy_send_timeout 600;
                    proxy_read_timeout 600;
                    send_timeout 600;

                    add_header 'Access-Control-Allow-Origin' $http_origin;
                    add_header 'Access-Control-Allow-Credentials' 'true';
                    add_header 'Access-Control-Allow-Headers' 'Authorization,Accept,Origin,DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Content-Range,Range';
                    add_header 'Access-Control-Allow-Methods' 'GET,POST,OPTIONS,PUT,DELETE,PATCH';
                  }
                }
              }
            ''; in {
          script = ''
            mkdir -p ${logDir}
            ${pkgs.nginx}/bin/nginx -c ${config} -g "daemon off;" -e ${logDir}/error.log
          '';
          serviceConfig.RunAtLoad = true;
          serviceConfig.KeepAlive = true;
        };
      };
    };
  };
}
