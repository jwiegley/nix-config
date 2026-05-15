{
  pkgs,
  lib,
  config,
  hostname,
  inputs,
  vulcan-crt,
  ...
}:

let
  home = "/Users/johnw";

  xdg_configHome = "${home}/.config";

in
{
  imports = [ ./launchd.nix ];

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
      # "zfs/zsysctl.conf".text = ''
      #   kstat.zfs.darwin.tunable.zfs_arc.max=34359738368
      # '';
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
      "withgraphite/tap"
      "jundot/omlx"
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
      "withgraphite/tap/graphite"
      "jundot/omlx/omlx"
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
      "claudebar"
      "conductor"
      "corelocationcli"
      "cursor"
      "cursor-cli"
      "dbvisualizer"
      "devonagent"
      "devonthink"
      "discord"
      "docker-desktop"
      "drivedx"
      "element"
      "fantastical"
      "github"
      "handy"
      "home-assistant"
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
      "netdownloadhelpercoapp"
      "opencode-desktop"
      "path-finder"
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
      # "vmware-fusion"
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

    overlays = import ./overlays.nix { inherit inputs vulcan-crt; };
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
        hostName = "vulcan.lan";
        protocol = "ssh-ng";
        systems = [
          "aarch64-linux"
          "x86_64-linux"
        ];
        sshUser = "johnw";
        sshKey = "${home}/hera/id_hera";
        maxJobs = 8;
        speedFactor = 2;
        supportedFeatures = [
          "nixos-test"
          "big-parallel"
          "kvm"
        ];
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

        trusted-substituters = [
          "https://cache.iog.io"
          "https://cache.nixos.org"
          "https://tron.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "newartisans.com:RmQd/aZOinbJR/G5t+3CIhIxT5NBjlCRvTiSbny8fYw="
          "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
          "tron.cachix.org-1:frKV7mquRWa4U3F0xjUtBehGgDzRofVj328awV2L+dQ="
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

    # Patch Homebrew formulas before `brew bundle` runs (extraActivation is
    # position 4 in the activation sequence; homebrew is position 23).
    activationScripts.extraActivation.text = ''
      # omlx formula: pyo3 extension modules need dynamic_lookup on macOS so
      # Python C API symbols resolve at runtime via the interpreter.
      # Upstream: https://github.com/jundot/omlx/issues/747
      FORMULA="/opt/homebrew/Library/Taps/jundot/homebrew-omlx/Formula/omlx.rb"
      if [ -f "$FORMULA" ] && ! grep -q 'RUSTFLAGS' "$FORMULA"; then
        echo >&2 "Patching omlx formula for pyo3 RUSTFLAGS..."
        ${pkgs.gnused}/bin/sed -i 's|ENV.append "LDFLAGS", "-Wl,-headerpad_max_install_names"|&\n\n    # pyo3 extension modules on macOS need dynamic_lookup\n    ENV.append "RUSTFLAGS", "-C link-arg=-undefined -C link-arg=dynamic_lookup"|' "$FORMULA"
      fi
    '';

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

}
