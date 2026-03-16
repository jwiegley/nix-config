{
  pkgs,
  lib,
  config,
  hostname,
  inputs,
  overlays,
  ...
}:

let
  home = "/Users/johnw";
  tmpdir = "/tmp";

  xdg_configHome = "${home}/.config";
  xdg_dataHome = "${home}/.local/share";
  xdg_cacheHome = "${home}/.cache";

in
{
  users = {
    # List of users and groups that nix-darwin is allowed to create/manage
    # CRITICAL: Users/groups must be in these lists for nix-darwin to create them
    knownUsers = [ "johnw" ] ++ lib.optionals (hostname != "clio") [ "_prometheus-node-exporter" ];
    knownGroups = lib.optionals (hostname != "clio") [ "_prometheus-node-exporter" ];

    users = {
      johnw = {
        name = "johnw";
        uid = 501;
        inherit home;
        shell = pkgs.zsh;

        openssh.authorizedKeys = {
          keys = [
            # GnuPG auth key stored on Yubikeys
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJAj2IzkXyXEl+ReCg9H+t55oa6GIiumPWeufcYCWy3F cardno:31_768_527"
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAING2r8bns7h9vZIfZSGsX+YmTSe2Tv1X8f/Qlqo+RGBb cardno:14_476_831"
          ];
          keyFiles =
            # Each machine accepts SSH key authentication from the rest
            import ./key-files.nix { inherit (pkgs) lib; } [ "hera" "clio" ] home hostname;
        };
      };

    }
    // lib.optionalAttrs (hostname != "clio") {
      # Prometheus node exporter user - match existing system user's home directory
      # On macOS, /var is a symlink to /private/var, but the user was created with
      # the canonical path, so we must force override the module's default
      _prometheus-node-exporter = {
        home = lib.mkForce "/private/var/lib/prometheus-node-exporter";
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

  environment = {
    systemPackages = with pkgs; [ ];

    etc = lib.mkIf (hostname == "hera") {
      # ZFS configuration for OpenZFS on macOS (hera only)
      # Sets ARC (Adaptive Replacement Cache) max to 32 GiB
      "zfs/zsysctl.conf".text = ''
        kstat.zfs.darwin.tunable.zfs_arc.max=34359738368
      '';
      "nsmb.conf".text = ''
        [default]
        signing_required=no
        mc_on=yes
        mc_prefer_wired=yes
        dir_cache_off=yes
        protocol_vers_map=6
      '';
    };
  };

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

  services = {
    # SSH daemon configuration to prevent connection slowness
    openssh = {
      enable = true;
      extraConfig = ''
        # Disable DNS reverse lookups to prevent connection delays
        UseDNS no

        # Disable GSSAPI authentication to prevent timeouts
        GSSAPIAuthentication no
      '';
    };

    prometheus.exporters.node = {
      enable = hostname != "clio";
      port = 9100;
      listenAddress = "0.0.0.0"; # Allow remote Prometheus to scrape
      enabledCollectors = [
        # Add additional collectors as needed
        # "systemd"  # Not available on macOS
      ];
    };

    # postgresql = {
    #   enable = true;
    #   package = pkgs.postgresql.withPackages (p: with p; [ pgvector ]);
    #   dataDir = "${home}/${hostname}/postgresql";
    #   authentication = ''
    #     local all all              trust
    #     host  all all localhost    trust
    #     host  all all 127.0.0.1/32 trust
    #   '';
    # };
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "zap"; # Remove uninstalled pkgs and dependencies
    };

    taps = [
      "graelo/tap"
      "steipete/tap"
      "antoniorodr/memo"
    ];
    brews = [
      "ykman"
      "nss"
      "node@22"
      "llm"
      "sqlcmd"
      "graelo/tap/pumas"
      "graelo/tap/huggingface-cli-full"
      "openssl"
      "z3"
      "claude-code-templates"
      "steipete/tap/remindctl"
      "steipete/tap/imsg"
      "antoniorodr/memo/memo"
    ];

    casks = [
      "1password"
      "1password-cli"
      "affinity-photo"
      "anki"
      "audacity"
      "balenaetcher"
      "carbon-copy-cloner"
      "cardhop"
      "choosy"
      "claude"
      "codexbar"
      "conductor"
      "corelocationcli"
      "dbvisualizer"
      "devonagent"
      "devonthink"
      "discord"
      "docker-desktop"
      "drivedx"
      "element"
      "fantastical"
      "geektool"
      "github"
      "handy"
      "iterm2"
      "itermai"
      "jump-desktop"
      "jump-desktop-connect"
      "key-codes"
      "keyboard-maestro"
      "kiwix"
      "launchbar"
      "lectrote"
      "ledger-wallet"
      "libreoffice"
      # "macfuse"
      "mactracker"
      "mellel"
      "microsoft-excel"
      "microsoft-powerpoint"
      "microsoft-word"
      "microsoft-remote-desktop"
      "netdownloadhelpercoapp"
      "opencode-desktop"
      "pdf-expert"
      "postman"
      "signal"
      "slack"
      "steam"
      "suspicious-package"
      "swiftdefaultappsprefpane"
      "tailscale-app"
      "telegram"
      "thinkorswim"
      "tor-browser"
      "ukelele"
      "unicodechecker"
      "virtual-ii"
      "visual-studio-code"
      "vlc"
      "vmware-fusion"
      "whatsapp"
      "wireshark-app"
      "wispr-flow"
      "xnviewmp"
      "zotero"
      # "datagraph"                 # Use DataGraph in App Store
      # "expandrive"
      # "macwhisper"                # Use Whisper Transcription in App Store
      # "marked-app"                # Use Marked 2 in App Store
      # "omnigraffle"               # Stay at version 6
      # "screenflow"                # Stay at version 9
      # "soulver"                   # Use Soulver 3 in App Store
      # "vagrant"
      # "vagrant-manager"
      # "vagrant-vmware-utility"
      {
        name = "brave-browser";
        greedy = true;
      }
      {
        name = "firefox";
        greedy = true;
      }
      {
        name = "opera";
        greedy = true;
      }
      {
        name = "vivaldi";
        greedy = true;
      }
      {
        name = "zoom";
        greedy = true;
      }
    ]
    ++ lib.optionals (hostname == "hera") [
      "elgato-stream-deck"
      "fujitsu-scansnap-home"
      "gzdoom"
      "home-assistant"
      # "logitune"
      "raspberry-pi-imager"
      "thunderbird"
      "utm"
    ]
    ++ lib.optionals (hostname == "clio") [
      "aldente"
      "wifi-explorer"
    ];

    ## The following software, or versions of software, are not available
    ## via Homebrew or the App Store:

    # "Bookmap"
    # "Digital Photo Professional"
    # "EOS Utility"
    # "MotiveWave"
    # "ScanSnap Online Update"
    # "Photo Supreme"
    # "ABBYY FineReader for ScanSnap"

    # masApps = {
    #   "1Password for Safari"  = 1569813296;
    #   "Apple Configurator"    = 1037126344;
    #   "Bible Study"           = 472790630;
    #   "DataGraph"             = 407412840;
    #   "Drafts"                = 1435957248;
    #   "Just Press Record"     = 1033342465;
    #   "Keynote"               = 409183694;
    #   "Kindle"                = 302584613;
    #   "Marked 2"              = 890031187;
    #   # "Microsoft Excel"       = 462058435;
    #   # "Microsoft PowerPoint"  = 462062816;
    #   # "Microsoft Word"        = 462054704;
    #   "Ninox Database"        = 901110441;
    #   "Paletter"              = 1494948845;
    #   "Pixelmator Pro"        = 1289583905;
    #   "Prime Video"           = 545519333;
    #   "Soulver 3"             = 1508732804;
    #   "Speedtest"             = 1153157709;
    #   "Whisper Transcription" = 1668083311;
    #   "WireGuard"             = 1451685025;
    #   "Xcode"                 = 497799835;
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
        # "python-2.7.18.7"
        # "libressl-3.4.3"
      ];
    };

    overlays = [
      # Inject flake inputs so overlays can access them via prev.inputs
      (final: prev: { inherit inputs; })
    ]
    ++ overlays
    ++ (
      let
        path = ../overlays;
      in
      with builtins;
      map (n: import (path + ("/" + n))) (
        filter (n: match ".*\\.nix" n != null || pathExists (path + ("/" + n + "/default.nix"))) (
          attrNames (readDir path)
        )
      )
    );
  };

  nix =
    let
      hera = {
        hostName = "hera.lan";
        protocol = "ssh-ng";
        system = "aarch64-darwin";
        sshUser = "johnw";
        maxJobs = 24;
        speedFactor = 4;
      };
      vulcan-builder = {
        hostName = "192.168.1.2";
        protocol = "ssh-ng";
        systems = [ "aarch64-linux" "x86_64-linux" ];
        sshUser = "johnw";
        sshKey = "${home}/hera/id_hera";
        maxJobs = 8;
        speedFactor = 2;
        supportedFeatures = [ "nixos-test" "big-parallel" "kvm" ];
      };
    in
    {

      enable = false;
      package = pkgs.nix;

      # This entry lets us to define a system registry entry so that
      # `nixpkgs#foo` will use the nixpkgs that nix-darwin was last built with,
      # rather than whatever is the current unstable version.
      #
      # See https://yusef.napora.org/blog/pinning-nixpkgs-flake
      # registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

      nixPath = lib.mkForce (
        lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry
        ++ [
          {
            ssh-config-file = "${home}/.ssh/config";
            darwin-config = "${home}/src/nix/config/darwin.nix";
            hm-config = "${home}/src/nix/config/home.nix";
          }
        ]
      );

      settings = {
        trusted-users = [
          "@admin"
          "@builders"
          "johnw"
        ];
        max-jobs = if (hostname == "clio") then 4 else 8;
        cores = 10;

        # Custom binary caches for better package availability
        substituters = [
          "https://cache.nixos.org"
          "https://cache.iog.io"
        ];
        trusted-substituters = [ "https://cache.iog.io" ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "newartisans.com:RmQd/aZOinbJR/G5t+3CIhIxT5NBjlCRvTiSbny8fYw="
          "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
        ];
      };

      distributedBuilds = true;
      buildMachines =
        (if hostname == "clio" then [ hera ] else [ ])
        ++ (if hostname == "hera" then [ vulcan-builder ] else [ ]);

      extraOptions = ''
        gc-keep-derivations = true
        gc-keep-outputs = true
        secret-key-files = ${xdg_configHome}/gnupg/nix-signing-key.sec
        experimental-features = nix-command flakes
      '';
    };

  ids.gids.nixbld = 350;

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
    # System daemons run as background services
    daemons =
      let
        iterate = StartInterval: {
          inherit StartInterval;
          Nice = 5;
          LowPriorityIO = true;
          AbandonProcessGroup = true;
        };
      in
      {
        limits = {
          script = ''
            /bin/launchctl limit maxfiles 524288 524288
            /bin/launchctl limit maxproc 8192 8192
          '';
          serviceConfig.RunAtLoad = true;
          serviceConfig.KeepAlive = false;
        };

        # cleanup = {
        #   script = ''
        #     export PYTHONPATH=$PYTHONPATH:${pkgs.dirscan}/libexec
        #     ${pkgs.python3}/bin/python ${pkgs.dirscan}/bin/cleanup -u \
        #         >> /var/log/cleanup.log 2>&1
        #   '';
        #   serviceConfig = iterate 86400;
        # };

        mssql-server = {
          script = ''
            # Wait for Docker to be ready
            while ! /usr/local/bin/docker info > /dev/null 2>&1; do
              echo "Waiting for Docker to be ready..."
              sleep 5
            done

            # Create data directory if it doesn't exist and set proper ownership
            # On macOS, Docker Desktop handles permission mapping internally
            mkdir -p ${home}/mssql
            chown -R johnw:staff ${home}/mssql

            # Create password file directory if it doesn't exist
            mkdir -p ${xdg_configHome}/mssql
            chown johnw:staff ${xdg_configHome}/mssql

            # Read password from secure file (must be created manually)
            # Create this file with: pass mssql.vulcan.lan > ~/.config/mssql/passwd && chmod 600 ~/.config/mssql/passwd
            if [ ! -f ${xdg_configHome}/mssql/passwd ]; then
              echo "ERROR: Password file ${xdg_configHome}/mssql/passwd not found"
              echo "Create it with: pass mssql.vulcan.lan > ~/.config/mssql/passwd && chmod 600 ~/.config/mssql/passwd"
              exit 1
            fi
            MSSQL_SA_PASSWORD=$(cat ${xdg_configHome}/mssql/passwd | tr -d '\n')

            # Validate password meets SQL Server requirements
            if [ ''${#MSSQL_SA_PASSWORD} -lt 8 ]; then
              echo "ERROR: Password must be at least 8 characters"
              exit 1
            fi

            # Pull the latest image if not present
            /usr/local/bin/docker pull mcr.microsoft.com/mssql/server:2022-latest

            # Stop and remove any existing container with the same name
            /usr/local/bin/docker rm -f mssql-server 2>/dev/null || true

            # Start the container with restart policy and persistent storage
            /usr/local/bin/docker run -d \
              --name mssql-server \
              --restart unless-stopped \
              -p 1433:1433 \
              -v ${home}/mssql:/var/opt/mssql \
              -e ACCEPT_EULA=Y \
              -e "MSSQL_SA_PASSWORD=$MSSQL_SA_PASSWORD" \
              mcr.microsoft.com/mssql/server:2022-latest
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

        llama-swap = {
          script = ''
            ${pkgs.llama-swap}/bin/llama-swap       \
            --listen "0.0.0.0:8080"           \
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
                client_body_temp_path ${logDir}/client_body;
                server {
                  listen 8443 ssl;

                  ssl_certificate /Users/johnw/hera/hera.lan.crt;
                  ssl_certificate_key /Users/johnw/hera/hera.lan.key;
                  ssl_protocols TLSv1.2 TLSv1.3;
                  ssl_prefer_server_ciphers on;
                  ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;

                  access_log ${logDir}/access.log;

                  # Proxy /v1/ requests to llama-swap
                  location /v1/ {
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

                  # Proxy all other requests to chat.vulcan.lan
                  location / {
                    proxy_pass https://chat.vulcan.lan;
                    proxy_ssl_verify off;

                    proxy_set_header Host chat.vulcan.lan;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;

                    proxy_connect_timeout 600;
                    proxy_send_timeout 600;
                    proxy_read_timeout 600;
                    send_timeout 600;

                    # WebSocket support for chat interface
                    proxy_http_version 1.1;
                    proxy_set_header Upgrade $http_upgrade;
                    proxy_set_header Connection "upgrade";
                  }
                }
              }
            '';
          in
          {
            script = ''
              mkdir -p ${logDir} ${logDir}/client_body
              ${pkgs.nginx}/bin/nginx -c ${config} -g "daemon off;" -e ${logDir}/error.log
            '';
            serviceConfig = {
              RunAtLoad = true;
              KeepAlive = true;
              SoftResourceLimits.NumberOfFiles = 4096;
            };
          };

      }
      // lib.optionalAttrs (hostname == "hera") {
        # OpenClaw AI agent gateway — runs inside a Docker Sandbox
        # (microVM isolation) with proxy bypass for Discord/WhatsApp,
        # and a socat bridge on the host to relay CLI traffic.
        #
        # After first switch, complete setup by running interactively:
        #   openclaw models auth setup-token --provider anthropic
        openclaw =
          let
            # ── Linux packages for Docker image ──────────────────────
            linuxPkgs = import inputs.nixpkgs {
              system = "aarch64-linux";
              config.allowUnfree = true;
            };

            openclawPkg = inputs.llm-agents.packages.aarch64-linux.openclaw;

            # Tools the gateway can invoke inside the container
            containerTools = with linuxPkgs; [
              bashInteractive
              coreutils
              findutils
              gnugrep
              gnused
              gawk
              gnutar
              git
              curl
              wget
              openssh
              rsync
              jq
              yq
              ripgrep
              fd
              bat
              (lib.hiPrio (
                python3.withPackages (pp: with pp; [
                  requests
                  numpy
                  pandas
                ])
              ))
              nodejs_22
              pnpm
              imagemagickBig
              ffmpeg
              sqlite
              cacert
              less
              tree
              watch
              vim
              htop
              lsof
              parallel
              xz
              unzip
              zip
              p7zip
              himalaya
              inputs.llm-agents.packages.aarch64-linux.mcporter
            ];

            # Vulcan private CA chain (Root + Intermediate) for *.vulcan.lan
            vulcanCaCerts = linuxPkgs.writeText "vulcan-ca.pem" ''
              -----BEGIN CERTIFICATE-----
              MIIB8DCCAZagAwIBAgIRALiwKWjq4Ooy1fXyoEM83rowCgYIKoZIzj0EAwIwVjEl
              MCMGA1UEChMcVnVsY2FuIENlcnRpZmljYXRlIEF1dGhvcml0eTEtMCsGA1UEAxMk
              VnVsY2FuIENlcnRpZmljYXRlIEF1dGhvcml0eSBSb290IENBMB4XDTI1MDkyMjIx
              MTMwNloXDTM1MDkyMDIxMTMwNlowVjElMCMGA1UEChMcVnVsY2FuIENlcnRpZmlj
              YXRlIEF1dGhvcml0eTEtMCsGA1UEAxMkVnVsY2FuIENlcnRpZmljYXRlIEF1dGhv
              cml0eSBSb290IENBMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAET6E9AE40v3h/
              1bMsspNWHO3riZ/LmVHqFGygt+LuXURbWDlmmWnabAkA/KbMoVlfYgD7nhhvwbQk
              j4l8GCUKL6NFMEMwDgYDVR0PAQH/BAQDAgEGMBIGA1UdEwEB/wQIMAYBAf8CAQEw
              HQYDVR0OBBYEFOT42u7UMDrYl8aw9bUKGoYB4gB9MAoGCCqGSM49BAMCA0gAMEUC
              IQDNoLb72lR2LG+hwibB5Ct2ApRHt5deqsbrlLsKMCtJsAIgFWJC/5p7Q7tdJtVi
              jImZjCO8EkfmTAdU4DnupnhJtU8=
              -----END CERTIFICATE-----
              -----BEGIN CERTIFICATE-----
              MIICGTCCAb6gAwIBAgIQBDc2EKqNFuV/17XrH7NVATAKBggqhkjOPQQDAjBWMSUw
              IwYDVQQKExxWdWxjYW4gQ2VydGlmaWNhdGUgQXV0aG9yaXR5MS0wKwYDVQQDEyRW
              dWxjYW4gQ2VydGlmaWNhdGUgQXV0aG9yaXR5IFJvb3QgQ0EwHhcNMjUwOTIyMjEx
              MzA3WhcNMzUwOTIwMjExMzA3WjBeMSUwIwYDVQQKExxWdWxjYW4gQ2VydGlmaWNh
              dGUgQXV0aG9yaXR5MTUwMwYDVQQDEyxWdWxjYW4gQ2VydGlmaWNhdGUgQXV0aG9y
              aXR5IEludGVybWVkaWF0ZSBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABNdo
              rYBZzxvQLHgTZo91lhWO+XfeDGIjITxGRpKlp94lllrnEpp7lHhoB/o4R+I7awJl
              QYycscn7EfvVbuILKEKjZjBkMA4GA1UdDwEB/wQEAwIBBjASBgNVHRMBAf8ECDAG
              AQH/AgEAMB0GA1UdDgQWBBQHQh6YNjacUN+ovo1CYxrgD7iOWjAfBgNVHSMEGDAW
              gBTk+Nru1DA62JfGsPW1ChqGAeIAfTAKBggqhkjOPQQDAgNJADBGAiEAudh3xyWI
              IY6R5dOwak9QJf1PF3Ac4IA9OMlOCIjMcM0CIQD+Rn1urtz4HW5KFDSTT8TDi9qX
              nML0GC5ZTlIeNxq6CA==
              -----END CERTIFICATE-----
            '';

            # Mozilla CAs + Vulcan private CA.
            # The Nix cacert bundle uses "TRUSTED CERTIFICATE" PEM markers
            # and includes human-readable label lines between certs.
            # Node.js's OpenSSL rejects those with "bad end line", causing
            # NODE_EXTRA_CA_CERTS to be silently ignored.  Sanitize to
            # standard "CERTIFICATE" markers with no inter-cert labels.
            combinedCaBundle = linuxPkgs.runCommand "combined-ca-bundle.crt" { } ''
              ${linuxPkgs.gawk}/bin/awk '
                /^-----BEGIN (TRUSTED )?CERTIFICATE-----/ {
                  p = 1
                  print "-----BEGIN CERTIFICATE-----"
                  next
                }
                /^-----END (TRUSTED )?CERTIFICATE-----/ {
                  p = 0
                  print "-----END CERTIFICATE-----"
                  print ""
                  next
                }
                p { print }
              ' ${linuxPkgs.cacert}/etc/ssl/certs/ca-bundle.crt > $out
              cat ${vulcanCaCerts} >> $out
            '';

            # Node.js preload that fixes proxy issues in Docker Sandbox:
            # (1) undici fetch() doesn't honor HTTPS_PROXY env var
            # (2) ws library's tls.connect() bypasses the proxy entirely
            proxySetupScript = linuxPkgs.runCommand "proxy-setup" {} ''
              UNDICI_IDX=$(find ${openclawPkg} \
                -path '*/node_modules/undici/index.js' \
                -not -path '*/undici-types/*' | head -1)
              if [ -z "$UNDICI_IDX" ]; then
                echo "ERROR: undici not found in ${openclawPkg}" >&2
                exit 1
              fi
              UNDICI_DIR=$(dirname "$UNDICI_IDX")

              mkdir -p $out/lib
              cat > $out/lib/proxy-setup.cjs << 'PROXYEOF'
"use strict";
var proxyEnv = process.env.HTTPS_PROXY || process.env.HTTP_PROXY || "";
if (!proxyEnv) return;
var proxyUrl = new (require("url").URL)(proxyEnv);
var PROXY_HOST = proxyUrl.hostname;
var PROXY_PORT = parseInt(proxyUrl.port, 10) || 3128;
var noProxyList = (process.env.NO_PROXY || "").split(",").map(function(s) { return s.trim(); });
try {
  var undici = require("__UNDICI_PATH__");
  undici.setGlobalDispatcher(new undici.EnvHttpProxyAgent());
} catch (_) {}
var tls = require("tls");
var net = require("net");
var Duplex = require("stream").Duplex;
var inherits = require("util").inherits;
function isLocal(host) {
  if (!host) return true;
  if (host === "127.0.0.1" || host === "::1" || host === "localhost") return true;
  if (host === PROXY_HOST || host.startsWith("host.docker.internal")) return true;
  for (var i = 0; i < noProxyList.length; i++) {
    var np = noProxyList[i];
    if (host === np || host.endsWith("." + np)) return true;
  }
  return false;
}
function ProxyTunnel(targetHost, targetPort) {
  Duplex.call(this);
  this.connecting = true;
  this._tunnelReady = false;
  this._writeBuffer = [];
  var self = this;
  this._sock = net.connect(PROXY_PORT, PROXY_HOST, function() {
    self._sock.write(
      "CONNECT " + targetHost + ":" + targetPort + " HTTP/1.1\r\n" +
      "Host: " + targetHost + ":" + targetPort + "\r\n\r\n"
    );
    var buf = Buffer.alloc(0);
    self._sock.on("data", function onData(chunk) {
      buf = Buffer.concat([buf, chunk]);
      var idx = buf.indexOf("\r\n\r\n");
      if (idx === -1) return;
      self._sock.removeListener("data", onData);
      var status = parseInt(buf.toString().split(" ")[1], 10);
      if (status !== 200) {
        self.destroy(new Error("Proxy CONNECT " + targetHost + ":" + targetPort + " failed: " + status));
        return;
      }
      var remainder = buf.slice(idx + 4);
      self._tunnelReady = true;
      self.connecting = false;
      self._sock.on("data", function(d) { self.push(d); });
      self._sock.on("end", function() { self.push(null); });
      self._sock.on("close", function() { self.destroy(); });
      if (remainder.length) self.push(remainder);
      var pending = self._writeBuffer;
      self._writeBuffer = [];
      for (var i = 0; i < pending.length; i++) {
        self._sock.write(pending[i].chunk, pending[i].enc, pending[i].cb);
      }
      self.emit("connect");
    });
  });
  this._sock.on("error", function(e) { self.destroy(e); });
}
inherits(ProxyTunnel, Duplex);
ProxyTunnel.prototype._read = function() {};
ProxyTunnel.prototype._write = function(chunk, enc, cb) {
  if (this._tunnelReady) return this._sock.write(chunk, enc, cb);
  this._writeBuffer.push({ chunk: chunk, enc: enc, cb: cb });
};
ProxyTunnel.prototype._final = function(cb) { this._sock.end(cb); };
ProxyTunnel.prototype._destroy = function(err, cb) {
  this._writeBuffer.forEach(function(w) { if (w.cb) w.cb(err); });
  this._writeBuffer = [];
  if (this._sock) this._sock.destroy();
  cb(err);
};
var origTlsConnect = tls.connect;
tls.connect = function proxyTlsConnect(options, cb) {
  var host = options.host || options.servername || "";
  var port = options.port || 443;
  if (options.socket || isLocal(host)) return origTlsConnect.call(tls, options, cb);
  var tunnel = new ProxyTunnel(host, port);
  var tlsOpts = Object.assign({}, options, { socket: tunnel });
  return origTlsConnect.call(tls, tlsOpts, cb);
};
PROXYEOF
              sed -i "s|__UNDICI_PATH__|$UNDICI_DIR|g" $out/lib/proxy-setup.cjs
            '';

            containerEnv = linuxPkgs.buildEnv {
              name = "openclaw-container-env";
              paths = containerTools ++ [ openclawPkg ];
              pathsToLink = [
                "/bin"
                "/lib"
                "/share"
                "/etc"
                "/include"
              ];
            };

            entrypoint = linuxPkgs.writeShellScript "openclaw-gateway-entrypoint" ''
              set -euo pipefail

              # Ensure required directories exist
              mkdir -p "$HOME/.openclaw/agents/main/sessions" \
                       "$HOME/.openclaw/logs" \
                       "$HOME/.openclaw/cron" \
                       "$HOME/.openclaw/delivery-queue"

              # Expose configs from the bind-mounted .openclaw directory
              # into paths where tools expect them.
              # mcporter: ~/.mcporter/mcporter.json
              if [ -d "$HOME/.openclaw/.mcporter" ]; then
                ln -sfn "$HOME/.openclaw/.mcporter" "$HOME/.mcporter"
              fi
              # himalaya: uses XDG or "Library/Application Support"
              if [ -d "$HOME/.openclaw/.himalaya" ]; then
                mkdir -p "$HOME/.config/himalaya"
                ln -sf "$HOME/.openclaw/.himalaya/config.toml" \
                  "$HOME/.config/himalaya/config.toml"
              fi

              # Rebuild sharp native module for linux-arm64 if needed.
              # This adds the linux binary alongside the darwin one in
              # the bind-mounted directory (both coexist peacefully since
              # they have different filenames).
              SHARP_REL="$HOME/.openclaw/workspace/skills/memory-qdrant/node_modules/sharp/build/Release"
              if [ -d "$SHARP_REL" ] && \
                 [ ! -f "$SHARP_REL/sharp-linux-arm64v8.node" ]; then
                echo "Installing sharp linux-arm64 binary..."
                cd "$HOME/.openclaw/workspace/skills/memory-qdrant"
                ${linuxPkgs.nodejs_22}/bin/npm rebuild sharp 2>&1 || true
                cd "$HOME"
              fi

              # Docker Sandbox blocks direct TCP to the host (network policy),
              # so host-local services (e.g. embeddings on port 8080) can't
              # be reached from the sandbox directly.  However, the sandbox's
              # MITM proxy (host.docker.internal:3128) runs on the host and
              # CAN forward HTTP requests to 127.0.0.1 on the host.
              #
              # OpenClaw's fetch() respects NO_PROXY (which includes
              # 127.0.0.1 and localhost to avoid breaking loopback traffic),
              # so we run a tiny bridge: listen on sandbox localhost:8080,
              # forward through the proxy to host 127.0.0.1:8080.
              HOST_TARGET="127.0.0.1"
              ${linuxPkgs.nodejs_22}/bin/node -e "
              const http = require('http');
              const PROXY = { host: 'host.docker.internal', port: 3128 };
              const TARGET = 'http://$HOST_TARGET:8080';
              http.createServer((req, res) => {
                const opts = {
                  hostname: PROXY.host, port: PROXY.port,
                  path: TARGET + req.url,
                  method: req.method,
                  headers: Object.assign({}, req.headers,
                    { host: '$HOST_TARGET:8080' })
                };
                const p = http.request(opts, (pr) => {
                  res.writeHead(pr.statusCode, pr.headers);
                  pr.pipe(res);
                });
                p.on('error', (e) => {
                  res.writeHead(502);
                  res.end('bridge: ' + e.message);
                });
                req.pipe(p);
              }).listen(8080, '127.0.0.1', () => {
                process.stdout.write('HTTP bridge: sandbox:8080 → host:8080 (via proxy)\\n');
              });
              " &

              # IMAP bridge: forward sandbox localhost:9993 → imap.vulcan.lan:993
              # via HTTP CONNECT tunnel through the sandbox proxy.
              # Himalaya (Rust CLI) can't use HTTP proxies for raw TLS/IMAP,
              # so we bridge with socat's PROXY address type.
              # Port 9993 (not 993) because the sandbox runs as non-root and
              # can't bind privileged ports (<1024).
              ${linuxPkgs.socat}/bin/socat \
                TCP-LISTEN:9993,bind=127.0.0.1,reuseaddr,fork \
                PROXY:host.docker.internal:imap.vulcan.lan:993,proxyport=3128 &
              echo "IMAP bridge: sandbox:9993 → imap.vulcan.lan:993 (via proxy)"

              # Build runtime CA bundle: static CAs + Docker Sandbox proxy CA.
              # Always overwrite — the bind-mounted file may be stale from a
              # previous run with a different Nix closure.
              CA_BUNDLE="$HOME/.openclaw/combined-ca.crt"
              rm -f "$CA_BUNDLE"
              cat ${combinedCaBundle} > "$CA_BUNDLE"
              if [ -n "''${PROXY_CA_CERT_B64:-}" ]; then
                printf '\n' >> "$CA_BUNDLE"
                printf '%s' "$PROXY_CA_CERT_B64" | base64 -d >> "$CA_BUNDLE"
              fi
              export SSL_CERT_FILE="$CA_BUNDLE"
              export NIX_SSL_CERT_FILE="$CA_BUNDLE"
              export NODE_EXTRA_CA_CERTS="$CA_BUNDLE"
              export REQUESTS_CA_BUNDLE="$CA_BUNDLE"

              exec ${openclawPkg}/bin/openclaw gateway run \
                --bind loopback --port 18789 --auth token
            '';

            # ── Docker image ─────────────────────────────────────────
            openclawImage = linuxPkgs.dockerTools.buildLayeredImage {
              name = "openclaw-gateway";
              tag = "latest";
              maxLayers = 80;

              contents = [ containerEnv linuxPkgs.socat proxySetupScript ];

              extraCommands = ''
                mkdir -p etc
                cat > etc/passwd <<EOF
                root:x:0:0:root:/root:/bin/sh
                nobody:x:65534:65534:Nobody:/nonexistent:/usr/sbin/nologin
                johnw:x:1000:1000:John Wiegley:/Users/johnw:${linuxPkgs.bashInteractive}/bin/bash
                EOF

                cat > etc/group <<EOF
                root:x:0:
                nogroup:x:65534:
                johnw:x:1000:johnw
                EOF

                echo "hosts: files dns" > etc/nsswitch.conf

                mkdir -p bin usr/bin
                ln -sf ${linuxPkgs.bashInteractive}/bin/bash bin/sh
                ln -sf ${linuxPkgs.bashInteractive}/bin/bash bin/bash
                ln -sf ${linuxPkgs.coreutils}/bin/env usr/bin/env
                ln -sf ${entrypoint} bin/openclaw-entrypoint

                mkdir -p Users/johnw/.openclaw
                mkdir -p Users/johnw/.cache
                mkdir -p Users/johnw/.local/share
                chmod -R 777 Users/johnw

                mkdir -p tmp
                chmod 1777 tmp

                # Docker Sandbox sets NODE_EXTRA_CA_CERTS and SSL_CERT_FILE
                # to /usr/local/share/ca-certificates/proxy-ca.crt.
                # Symlink to our combined CA bundle so that tools launched
                # via 'docker sandbox exec' also validate TLS properly.
                mkdir -p usr/local/share/ca-certificates
                ln -sf /Users/johnw/.openclaw/combined-ca.crt \
                  usr/local/share/ca-certificates/proxy-ca.crt
              '';

              config = {
                Cmd = [ "/bin/openclaw-entrypoint" ];
                User = "johnw";
                WorkingDir = "/Users/johnw";
                Env = [
                  "PATH=${containerEnv}/bin:/usr/local/bin:/usr/bin:/bin"
                  "HOME=/Users/johnw"
                  "USER=johnw"
                  "TERM=xterm-256color"
                  "LANG=C.UTF-8"
                  "TZ=PST8PDT"
                  "TZDIR=${linuxPkgs.tzdata}/share/zoneinfo"
                  "SSL_CERT_FILE=${combinedCaBundle}"
                  "NIX_SSL_CERT_FILE=${combinedCaBundle}"
                  "NODE_EXTRA_CA_CERTS=${combinedCaBundle}"
                  "HTTPS_PROXY=http://host.docker.internal:3128"
                  "HTTP_PROXY=http://host.docker.internal:3128"
                  "NO_PROXY=127.0.0.1,localhost,::1,host.docker.internal"
                  "NODE_OPTIONS=--require ${proxySetupScript}/lib/proxy-setup.cjs"
                ];
                Labels = {
                  "org.opencontainers.image.description" =
                    "OpenClaw gateway — sandboxed agent execution";
                };
              };
            };

            logDir = "${xdg_cacheHome}/openclaw";
            docker = "/usr/local/bin/docker";
            socat = "${pkgs.socat}/bin/socat";
            imageMarker = "${xdg_cacheHome}/openclaw/.image-loaded";
            sandboxMarker = "${xdg_cacheHome}/openclaw/.sandbox-image";

            # Domains that need direct TLS (bypass MITM proxy).
            # Vulcan LAN services use a private CA; bypassing avoids
            # MITM re-signing complexity.  WhatsApp uses numbered edge
            # servers (w1–w20.web.whatsapp.com).
            bypassHosts = [
              # Discord
              "discord.com" "gateway.discord.gg" "cdn.discordapp.com"
              "discordapp.com" "discord.gg"
              # WhatsApp — main + numbered edge servers
              "web.whatsapp.com" "pps.whatsapp.net" "mmg.whatsapp.net"
              "g.whatsapp.net" "static.whatsapp.net" "media.whatsapp.net"
            ] ++ (map (n: "w${toString n}.web.whatsapp.com")
                      (lib.range 1 20))
            ++ [
              # Vulcan LAN (private CA) — each subdomain must be listed
              # explicitly; "vulcan.lan" only matches the bare domain, not
              # *.vulcan.lan subdomains.
              "litellm.vulcan.lan" "qdrant.vulcan.lan" "vulcan.lan"
              "hass.vulcan.lan" "imap.vulcan.lan"
            ];
            bypassFlags = lib.concatMapStringsSep " "
              (h: "--bypass-host ${h}") bypassHosts;
          in
          {
            script = ''
              # docker push needs docker-credential-desktop in PATH
              export PATH="/usr/local/bin:$PATH"

              mkdir -p "${logDir}" "${home}/.openclaw/agents/main/sessions"

              # Docker Sandbox resolves template images from within its
              # microVM, so a local registry is needed.  Push via
              # localhost:5050; sandbox pulls via host.docker.internal:5050.
              # Port 5050 avoids macOS AirPlay on 5000.  Requires
              # insecure-registries ["host.docker.internal:5050"] in the
              # Docker Desktop engine config.
              REGISTRY_PORT=5050
              # Use a content-hash tag to bust the sandbox containerd cache.
              # The sandbox caches images by tag; 'latest' resolves to a stale
              # digest even after a push.  A unique tag forces a fresh pull.
              IMAGE_HASH=$(basename "${openclawImage}" | cut -c1-12)
              PUSH_IMAGE="localhost:$REGISTRY_PORT/openclaw-gateway:$IMAGE_HASH"
              SANDBOX_IMAGE="host.docker.internal:$REGISTRY_PORT/openclaw-gateway:$IMAGE_HASH"
              if ! ${docker} ps --filter name=nix-registry --format '{{.Names}}' \
                   | grep -q nix-registry 2>/dev/null; then
                ${docker} rm -f nix-registry 2>/dev/null || true
                ${docker} run -d \
                  -p 0.0.0.0:$REGISTRY_PORT:5000 \
                  --name nix-registry \
                  --restart always \
                  registry:2
                sleep 2
              fi

              # Load and push image only when the Nix store path changes
              IMAGE_PATH="${openclawImage}"
              if [ ! -f "${imageMarker}" ] || \
                 [ "$(cat "${imageMarker}" 2>/dev/null)" != "$IMAGE_PATH" ]; then
                echo "Loading new OpenClaw Docker image..."
                ${docker} load < "$IMAGE_PATH"
                ${docker} tag openclaw-gateway:latest "$PUSH_IMAGE"
                echo "Pushing to local registry..."
                ${docker} push "$PUSH_IMAGE"
                echo "$IMAGE_PATH" > "${imageMarker}"
              fi

              # Helper: create sandbox with retry (sandboxd can transiently
              # fail with "failed to load cached tar" right after Docker restart)
              create_sandbox() {
                for attempt in 1 2 3; do
                  ${docker} sandbox rm openclaw-gateway 2>/dev/null || true
                  if ${docker} sandbox create \
                       --name openclaw-gateway \
                       --template "$SANDBOX_IMAGE" \
                       shell "${home}/.openclaw" 2>&1; then
                    return 0
                  fi
                  echo "Sandbox creation attempt $attempt failed — retrying in 10s..."
                  sleep 10
                done
                echo "ERROR: sandbox creation failed after 3 attempts"
                return 1
              }

              # Create or recreate sandbox when image changes
              if [ ! -f "${sandboxMarker}" ] || \
                 [ "$(cat "${sandboxMarker}" 2>/dev/null)" != "$IMAGE_PATH" ]; then
                echo "Recreating OpenClaw sandbox with updated image..."
                ${docker} sandbox stop openclaw-gateway 2>/dev/null || true
                create_sandbox
                echo "$IMAGE_PATH" > "${sandboxMarker}"
              else
                # Sandbox exists but may be stopped (e.g. after Docker restart)
                if ! ${docker} sandbox exec openclaw-gateway true 2>/dev/null; then
                  echo "Sandbox stopped — recreating..."
                  create_sandbox
                fi
              fi

              # Configure proxy bypass for services that need direct TLS.
              # Also allow-cidr 127.0.0.0/8 so the HTTP bridge can forward
              # requests through the proxy to host localhost services
              # (embeddings on port 8080).
              ${docker} sandbox network proxy openclaw-gateway \
                ${bypassFlags} \
                --allow-cidr 127.0.0.0/8

              # Stop any existing gateway process from a previous run.
              # Without this, a service restart would leave the old gateway
              # listening on :18789 inside the sandbox, and the new
              # entrypoint would fail to bind the port.
              # The gateway lock is at /tmp/openclaw-<uid>/gateway.*.lock
              ${docker} sandbox exec openclaw-gateway \
                ${openclawPkg}/bin/openclaw gateway stop 2>/dev/null || true
              # Give the old process time to release the port
              sleep 2

              # Wait for proxy bypass rules to propagate.  The gateway's
              # initial Discord/Qdrant fetches fail with "fetch failed" if
              # the entrypoint starts before the bypass is active.
              sleep 3

              # Sandbox /etc/hosts is read-only for non-root.  Add
              # imap.vulcan.lan → 127.0.0.1 so himalaya's TLS hostname
              # verification matches the server cert when connecting via
              # the local socat IMAP bridge.
              ${docker} sandbox exec --user root openclaw-gateway \
                sh -c 'grep -q imap.vulcan.lan /etc/hosts 2>/dev/null || echo "127.0.0.1 imap.vulcan.lan" >> /etc/hosts'

              # Run the gateway entrypoint inside the sandbox.
              # Use the fixed /bin/openclaw-entrypoint symlink rather than
              # the Nix store path, which changes on every rebuild and may
              # not match the sandbox's cached image layers.
              ${docker} sandbox exec -d \
                -e HOME=/Users/johnw \
                openclaw-gateway \
                /bin/openclaw-entrypoint

              # Wait for the gateway to be ready inside the sandbox
              for i in $(seq 1 60); do
                if ${docker} sandbox exec openclaw-gateway \
                     curl -sf http://127.0.0.1:18789/ >/dev/null 2>&1; then
                  break
                fi
                sleep 1
              done

              echo "Gateway sandbox ready — starting socat bridge"

              # Health monitor + keepalive: runs every 30s to:
              # 1. Detect gateway crashes (3 consecutive failures → restart)
              # 2. Keep the sandbox VM alive (Docker API activity resets the
              #    sandbox daemon's 1800s idle timeout, which otherwise kills
              #    the VM even while the gateway is actively serving)
              (
                FAILURES=0
                while sleep 30; do
                  if ${docker} sandbox exec openclaw-gateway \
                       curl -sf http://127.0.0.1:18789/ >/dev/null 2>&1; then
                    FAILURES=0
                  else
                    FAILURES=$((FAILURES + 1))
                    echo "Health check failed ($FAILURES/3)"
                    if [ $FAILURES -ge 3 ]; then
                      echo "Gateway unresponsive — killing socat to trigger restart"
                      kill $$ 2>/dev/null || true
                      exit 1
                    fi
                  fi
                done
              ) &

              # Bridge host loopback → sandbox loopback via docker sandbox exec
              exec ${socat} \
                TCP-LISTEN:18789,bind=127.0.0.1,reuseaddr,fork \
                EXEC:"${docker} sandbox exec -i openclaw-gateway ${linuxPkgs.socat}/bin/socat - TCP\:127.0.0.1\:18789"
            '';
            serviceConfig = {
              Label = "ai.openclaw.gateway";
              EnvironmentVariables = {
                HOME = home;
              };
              RunAtLoad = true;
              KeepAlive = true;
              ThrottleInterval = 30;
              StandardOutPath = "${logDir}/gateway.log";
              StandardErrorPath = "${logDir}/gateway.log";
            };
          };

        docker-desktop = {
          script = ''
            # Start Docker Desktop
            /usr/bin/open -a "/Applications/Docker.app"
          '';
          serviceConfig = {
            RunAtLoad = true;
            KeepAlive = false; # Don't restart - Docker manages itself
            ProcessType = "Interactive"; # GUI application
          };
        };

        autossh-vps = {
          script = ''
            export AUTOSSH_GATETIME=0
            export SSH_AUTH_SOCK="${xdg_configHome}/gnupg/S.gpg-agent.ssh"
            ${pkgs.autossh}/bin/autossh -M 0 -N vps -C \
                -o "ControlMaster=no"                  \
                -o "ControlPath=none"                  \
                -o "ServerAliveInterval=30"            \
                -o "ServerAliveCountMax=3"             \
                -o "ExitOnForwardFailure=yes"          \
                -L 127.0.0.1:15432:127.0.0.1:5432      \
                -R 127.0.0.1:8317:127.0.0.1:8317       \
                -R 127.0.0.1:8090:127.0.0.1:8080       \
                -R 127.0.0.1:9222:127.0.0.1:9222
          '';
          serviceConfig = {
            RunAtLoad = true;
            KeepAlive = true;
            ThrottleInterval = 30; # Wait 30s between restart attempts
            StandardOutPath = "${xdg_cacheHome}/autossh-vps.log";
            StandardErrorPath = "${xdg_cacheHome}/autossh-vps.log";
          };
        };

        vlc-telnet = {
          script = ''
            /Applications/VLC.app/Contents/MacOS/VLC \
                -I telnet                            \
                --telnet-password=secret             \
                --telnet-port=4212
          '';
          serviceConfig.RunAtLoad = true;
          serviceConfig.KeepAlive = true;
        };

        chrome-debug = {
          script = ''
            /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
                --headless=new \
                --remote-debugging-port=9223 \
                --user-data-dir=/tmp/chrome-debug
          '';
          serviceConfig.RunAtLoad = true;
          serviceConfig.KeepAlive = true;
        };

        chrome-debug-proxy = {
          script = ''
            # Wait for Chrome to start listening on internal port
            while ! /usr/bin/nc -z 127.0.0.1 9223 2>/dev/null; do
              sleep 1
            done
            # Forward 0.0.0.0:9222 to localhost:9223
            ${pkgs.socat}/bin/socat TCP-LISTEN:9222,bind=0.0.0.0,fork,reuseaddr TCP:127.0.0.1:9223
          '';
          serviceConfig.RunAtLoad = true;
          serviceConfig.KeepAlive = true;
        };

        flatten-recordings = {
          script = ''
            # Move .m4a files from subdirectories of ~/Recordings into ~/Recordings
            recordings_dir="${home}/Recordings/"

            # Move only .m4a files from subdirectories up to ~/Recordings
            if [ -d "$recordings_dir" ]; then
              find -L "$recordings_dir" -mindepth 2 -type f -name "*.m4a" -exec mv {} "$recordings_dir" \;

              # Remove .DS_Store files that macOS creates
              find -L "$recordings_dir" -mindepth 2 -name ".DS_Store" -delete

              # Remove empty subdirectories (using rmdir which only removes empty dirs)
              find -L "$recordings_dir" -mindepth 1 -type d -depth -exec rmdir {} \; 2>/dev/null || true
            fi
          '';
          serviceConfig = {
            StartInterval = 900; # Run every 15 minutes (900 seconds)
            RunAtLoad = true; # Run once at startup
          };
        };
      };
    };
  };

}
