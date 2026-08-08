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
  imports = [
    ./launchd.nix
    ./host-options.nix
  ];

  # Prevent macOS from falling back to the case-preserving LocalHostName.
  networking.hostName = hostname;

  users = {
    # nix-darwin's Prometheus module registers its own service account when the
    # exporter is enabled; only the login user belongs in this local declaration.
    knownUsers = [ "johnw" ];

    users = {
      johnw = {
        name = "johnw";
        uid = 501;
        inherit home;
        shell = pkgs.zsh;

        openssh.authorizedKeys = {
          keys =
            let
              modelMetadataExtract = pkgs.writeShellScript "model-metadata-extract" ''
                exec ${pkgs.gawk}/bin/awk '
                  BEGIN{IGNORECASE=1}
                  /api.?key|token|secret|password|bearer/ { next }
                  /^[[:space:]]{2,4}[^[:space:]#][^:]*:[[:space:]]*$/ {
                    k=$0; sub(/:[[:space:]]*$/,"",k); gsub(/^[[:space:]]+/,"",k); print "MODEL\t" k; next }
                  {
                    for(i=1;i<=NF;i++){
                      if($i=="--ctx-size"||$i=="-c")   print "CTX\t"  $(i+1)+0
                      else if($i=="--n-predict")       print "NPRED\t" $(i+1)+0
                      else if($i=="--jinja")           print "FLAG\tjinja"
                      else if($i=="--reasoning-format")print "FLAG\treasoning-format=" $(i+1)
                      else if($i=="--embeddings"||$i=="--embedding") print "FLAG\tembeddings"
                      else if($i=="--pooling")         print "FLAG\tpooling"
                    }
                  }' /Users/johnw/Models/llama-swap.yaml
              '';
            in
            [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJAj2IzkXyXEl+ReCg9H+t55oa6GIiumPWeufcYCWy3F cardno:31_768_527"
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAING2r8bns7h9vZIfZSGsX+YmTSe2Tv1X8f/Qlqo+RGBb cardno:14_476_831"

              ''restrict,command="${modelMetadataExtract}" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFZYNrQfHWNV09OQz7uMhjQKflCWKwLG4pp1tJb2QRRq vulcan-model-metadata''

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
    // lib.optionalAttrs (!config.johnw.host.isClio) {
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
      lib.optionals config.johnw.host.isDarwinWorkstation [
        eternal-terminal
      ];

    etc = lib.mkIf config.johnw.host.isHera {
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

  # Start GnuPG through its canonical sockets at login. The bootstrap exits
  # after gpg-agent daemonizes, so launchd never supervises or crash-loops it.
  launchd.user.agents.gnupg-agent.serviceConfig = {
    EnvironmentVariables.GNUPGHOME = "${xdg_configHome}/gnupg";
    KeepAlive = lib.mkForce false;
    RunAtLoad = lib.mkForce true;
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
      enable = !config.johnw.host.isClio;
      port = 9100;
      listenAddress = "0.0.0.0"; # Allow remote Prometheus to scrape
      enabledCollectors = [
        # Add additional collectors as needed
        # "systemd"  # Not available on macOS
      ];
    };

  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      # Remove packages without Homebrew Bundle's generic force-install flag.
      cleanup = "uninstall"; # Remove packages absent from the Brewfile.
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
      "chatgpt"
      "choosy"
      "claude"
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
      "factory"
      "fantastical"
      "github"
      "google-gemini"
      "handy"
      "hermes-desktop"
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
      "mactracker"
      "mellel"
      "microsoft-excel"
      "microsoft-powerpoint"
      "microsoft-word"
      "netdownloadhelpercoapp"
      "obsidian"
      "path-finder"
      "pdf-expert"
      "postman"
      "shottr"
      "signal"
      "slack"
      "steam"
      "suspicious-package"
      # Installed by request; Home Manager remains the sole runtime owner.
      # Syncthing.app must remain closed while that daemon is enabled.
      "syncthing-app"
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
    ++ lib.optionals config.johnw.host.isHera [
      "chronoagent"
      "elgato-stream-deck"
      "fujitsu-scansnap-home"
      "gzdoom"
      "raspberry-pi-imager"
      "thunderbird"
      "utm"
    ]
    ++ lib.optionals config.johnw.host.isClio [
      "aldente"
      "betterdisplay"
      "chronosync"
      "wifi-explorer"
    ];
  };

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowBroken = false;
      allowInsecure = false;
      allowUnsupportedSystem = false;
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
        max-jobs = if config.johnw.host.isClio then 4 else 8;
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
        (if config.johnw.host.isClio then [ hera ] else [ ])
        ++ (if config.johnw.host.isHera then [ vulcan-builder ] else [ ]);

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

    # Homebrew enforces tap trust during nix-darwin's Homebrew activation
    # before Home Manager links files. It also rejects trust stores whose real
    # path lives under the root-owned Nix store, so this must be a real user-owned
    # file in ~/.homebrew rather than a home.file symlink.
    activationScripts.preActivation.text = ''
      /usr/bin/install -d -o johnw -g staff -m 0755 ${home}/.homebrew
      /bin/rm -f ${home}/.homebrew/trust.json
      /usr/bin/install -o johnw -g staff -m 0644 ${homebrewTrustJson} ${home}/.homebrew/trust.json
    '';

    # Hera hosts LLM services continuously. Reapply sleep=0 on each activation;
    # disksleep and displaysleep remain user-managed.
    activationScripts.postActivation.text = lib.mkIf config.johnw.host.isHera ''
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
        _HIHideMenuBar = !config.johnw.host.isClio;
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

        # The cask is installed by request, but its bundled daemon must not race
        # the Home Manager service or self-update outside the Nix rollout.
        "com.github.xor-gate.syncthing-macosx" = {
          StartAtLogin = false;
          SUEnableAutomaticChecks = false;
          SUAutomaticallyUpdate = false;
        };

        "com.apple.spaces" = {
          "spans-displays" = 0; # Displays have separate spaces
        };

        "com.apple.WindowManager" = {
          EnableStandardClickToShowDesktop = 0; # Disable click-wallpaper-to-reveal-desktop
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
        orientation = if config.johnw.host.isClio then "left" else "right";
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
