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

  homebrewTrustJson = pkgs.writeText "homebrew-trust.json" (
    builtins.toJSON {
      trustedtaps = [
        "graelo/tap"
        "withgraphite/tap"
      ];
      trustedformulae = [
        "graelo/tap/pumas"
        "withgraphite/tap/graphite"
      ];
    }
  );
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

            # drafts-mcp bridge (vulcan drafts-mcp.service) — pinned to exec
            # drafts-mcp-server ONLY; SSH_ORIGINAL_COMMAND is ignored by the
            # forced command. `restrict` disables pty/forwarding/X11/agent.
            # This is the per-key least-privilege gate (NOT key-files.nix,
            # which grants an unrestricted login shell).
            "command=\"/etc/profiles/per-user/johnw/bin/drafts-mcp-server\",restrict,no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfhC6rPhjkSucPkTuL+On43E4udAss806oVAqNso3Qy drafts-bridge@vulcan"
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
    systemPackages =
      with pkgs;
      lib.optionals
        (lib.elem hostname [
          "hera"
          "clio"
        ])
        [
          eternal-terminal
        ];

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
      # NOTE: nix-darwin's `homebrew` module turns `onActivation.cleanup` into
      # flags on the implicit `brew bundle install` run during activation:
      #   cleanup = "uninstall" -> `brew bundle ... --cleanup`
      #   cleanup = "zap"       -> `brew bundle ... --cleanup --zap`
      # with anything in `extraFlags` appended right after `--cleanup`.
      #
      # What `--cleanup` *requires* differs by Homebrew version, which is why a
      # config that worked on one machine failed on another with a different
      # brew:
      #   * Some intermediate Homebrew 5.1.x refused a bare `--cleanup`
      #     non-interactively: `Invalid usage: brew bundle install --cleanup
      #     requires --force, --force-cleanup or $HOMEBREW_ASK`.
      #   * Homebrew 5.1.14 dropped `--force-cleanup` entirely (it is no longer
      #     a valid `brew bundle install` option) and made `--cleanup` mean
      #     "same as cleanup --force" -- i.e. already forced/non-interactive.
      #     Passing `--force-cleanup` there fails during `u <host>
      #     upgrade-tasks` with `Error: invalid option: --force-cleanup`.
      # So `--force-cleanup` is NOT portable across brew versions. `--force`
      # is: older brew lists it as an accepted alternative, and 5.1.14 still
      # accepts it (harmless there, since `--cleanup` is already forced). Hence
      # `extraFlags = [ "--force" ]` works on every brew we run.
      #
      # The locked nix-darwin still emits a bare `--cleanup` for "uninstall"
      # (upstream fixes so far only address the "zap" path), so no `darwin`
      # input bump removes the need for this. We keep "uninstall" so brews/casks
      # dropped from the lists below are still removed, and avoid $HOMEBREW_ASK
      # (it makes activation interactive, which is bad for automated switches).
      cleanup = "uninstall"; # Remove uninstalled pkgs and dependencies
      extraFlags = [ "--force" ]; # portable force flag for `brew bundle --cleanup`
    };

    taps = [
      "graelo/tap"
      "withgraphite/tap"
    ];
    brews = [
      "ykman"
      "nss"
      "node@22"
      "llm"
      "sqlcmd"
      "graelo/tap/pumas"
      "hf"
      "openssl"
      "z3"
      "claude-code-templates"
      "withgraphite/tap/graphite"
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
      # "dropzone"
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
      "shottr"
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
      "whimsical"
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
      "betterdisplay"
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

    # Homebrew 5.1.x enforces tap trust during nix-darwin's Homebrew activation
    # before Home Manager links files. It also rejects trust stores whose real
    # path lives under the root-owned Nix store, so this must be a real user-owned
    # file in ~/.homebrew rather than a home.file symlink.
    activationScripts.preActivation.text = ''
      /usr/bin/install -d -o johnw -g staff -m 0755 ${home}/.homebrew
      /bin/rm -f ${home}/.homebrew/trust.json
      /usr/bin/install -o johnw -g staff -m 0644 ${homebrewTrustJson} ${home}/.homebrew/trust.json
    '';

    # Hera is a desktop and hosts LLM services that need to stay reachable
    # at any hour. Force the configured value so it can't drift back via
    # System Settings or `pmset` from another shell. disksleep/displaysleep
    # are intentionally left unmanaged so they can still be tuned via the
    # Settings app.
    activationScripts.postActivation.text = lib.mkIf (hostname == "hera") ''
      /usr/bin/pmset -a sleep 0
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
        orientation = if hostname == "clio" then "left" else "right";
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
