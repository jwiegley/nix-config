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
  nixTrust = import ./nix-trust.nix;

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

  # Hera is the only remote inference host. Vulcan and Clio reach this listener
  # over their declared network paths; oMLX remains the authentication authority.
  johnw.omlxProxy = lib.mkIf config.johnw.host.isHera {
    enable = true;
    listenAddress = "192.168.1.4";
    allowedSources = [
      "192.168.1.2/32"
      "192.168.1.5/32"
      "10.6.0.2/32"
    ];
  };

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
            ]
            ++ lib.optionals config.johnw.host.isHera [
              # pushme positron sync (vulcan pushme-positron.timer) — JUMP HOST ONLY.
              # ProxyJump opens direct-tcpip without invoking the forced command. The
              # Hera-only sshd Match below permits local forwarding only; this key then
              # narrows that capability to Andoria. /usr/bin/false closes session/exec
              # channels. No shell, remote forward, pty, agent, or X11.
              ''from="192.168.1.2",restrict,port-forwarding,permitopen="andoria-08:22",command="/usr/bin/false" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID/5S98ifv/slBhGzSLMK+/3JAHNzzglOfau6RlqKeYs johnw@vulcan''
            ]
            ++ [
              # drafts-mcp bridge (vulcan drafts-mcp.service) — pinned to exec
              # drafts-mcp-server ONLY; SSH_ORIGINAL_COMMAND is ignored by the
              # forced command. `restrict` disables pty/forwarding/X11/agent.
              # This is the per-key least-privilege gate (NOT key-files.nix,
              # which grants an unrestricted login shell).
              "command=\"/etc/profiles/per-user/johnw/bin/drafts-mcp-server\",restrict,no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfhC6rPhjkSucPkTuL+On43E4udAss806oVAqNso3Qy drafts-bridge@vulcan"
            ];
          keyFiles =
            # Each machine accepts SSH key authentication from the rest
            import ./key-files.nix { inherit (pkgs) lib; } [ "hera" "clio" ] hostname;
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

    etc = lib.mkMerge [
      (lib.mkIf config.johnw.host.isHera {
        "nsmb.conf".text = ''
          [default]
          signing_required=no
          mc_on=yes
          mc_prefer_wired=yes
          dir_cache_off=yes
          protocol_vers_map=6
        '';
      })
      {
        # Determinate owns the daemon (`nix.enable = false`), so nix-darwin
        # does not emit this file from `nix.buildMachines` for us.
        "nix/machines" = {
          knownSha256Hashes =
            lib.optionals config.johnw.host.isHera [
              "46f63cb24e8924d42d09c6dfcb50b9c4c64c84b137d65ee65f21b4c9f07403ef"
            ]
            ++ lib.optionals config.johnw.host.isClio [
              "44c02435dbd05dabf4b972e9575d4ddeceba5d9eca7b30d7788a8388971a85f1"
            ];
          text = lib.concatMapStrings (
            machine:
            let
              features = machine.supportedFeatures ++ machine.mandatoryFeatures;
            in
            lib.concatStringsSep " " [
              "${lib.optionalString (machine.protocol != null) "${machine.protocol}://"}${
                lib.optionalString (machine.sshUser != null) "${machine.sshUser}@"
              }${machine.hostName}"
              (
                if machine.system != null then
                  machine.system
                else if machine.systems != [ ] then
                  lib.concatStringsSep "," machine.systems
                else
                  "-"
              )
              (if machine.sshKey != null then machine.sshKey else "-")
              (toString machine.maxJobs)
              (toString machine.speedFactor)
              (if features == [ ] then "-" else lib.concatStringsSep "," features)
              (
                if machine.mandatoryFeatures == [ ] then "-" else lib.concatStringsSep "," machine.mandatoryFeatures
              )
              (if machine.publicHostKey != null then machine.publicHostKey else "-")
            ]
            + "\n"
          ) config.nix.buildMachines;
        };
      }
      (lib.mkIf config.johnw.host.isClio {
        "nix/builder-known-hosts".text = ''
          hera.lan ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE92Mnzmx/CVS6GiGbJ1vGC0Sdf+D7/vSU/PN7f1Y1MV
        '';
        "ssh/ssh_config.d/050-nix-builders.conf".text = ''
          Host andoria-08 andoria-t2
            ProxyCommand ssh -o BatchMode=yes -o IdentitiesOnly=yes -o UserKnownHostsFile=/etc/nix/builder-known-hosts -o StrictHostKeyChecking=yes -i ${home}/${hostname}/id_${hostname} -W %h:%p johnw@hera.lan
        '';
      })
    ];
  };

  assertions = [
    {
      assertion = builtins.all (
        machine: machine.system != null || machine.systems != [ ]
      ) config.nix.buildMachines;
      message = "every Nix build machine must declare at least one system";
    }
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
      ''
      + lib.optionalString config.johnw.host.isHera ''

        # The Vulcan jump key may open direct-tcpip only. authorized_keys can
        # restrict its destination, but forwarding direction is sshd policy.
        Match User johnw Address 192.168.1.2
          AllowStreamLocalForwarding no
          AllowTcpForwarding local
          PermitListen none
        Match all
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
      "elgato-stream-deck"
      "factory"
      "fantastical"
      "fujitsu-scansnap-home"
      "github"
      "google-gemini"
      "gzdoom"
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
      "raspberry-pi-imager"
      "shottr"
      "signal"
      "slack"
      "steam"
      "suspicious-package"
      "swiftdefaultappsprefpane"
      # Installed by request; Home Manager remains the sole runtime owner.
      # Syncthing.app must remain closed while that daemon is enabled.
      "syncthing-app"
      "tailscale-app"
      "telegram"
      "thinkorswim"
      "thunderbird"
      "tor-browser"
      "ukelele"
      "unicodechecker"
      "utm"
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
      hostRegistry = import ./hosts/registry.nix;
      builderIdentityPaths = {
        host = "${home}/${hostname}/id_${hostname}";
        positron = "${xdg_configHome}/ssh/id_positron";
      };
      buildMachineFor =
        name:
        let
          builder = hostRegistry.builders.${name};
        in
        builtins.removeAttrs builder [ "sshIdentity" ]
        // {
          sshKey = builderIdentityPaths.${builder.sshIdentity};
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

        trusted-substituters = nixTrust.darwin.trustedSubstituters;
        trusted-public-keys = nixTrust.darwin.trustedPublicKeys;
      };

      distributedBuilds = true;
      buildMachines = map buildMachineFor hostRegistry.builderPools.${hostname};

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

    activationScripts.postActivation.text = ''
      # nix-darwin does not reload Determinate's daemon when `nix.enable = false`.
      # Compare against the previous generation, which is still current here.
      if ! /usr/bin/cmp -s /run/current-system/etc/nix/machines ${
        config.environment.etc."nix/machines".source
      }; then
        echo "reloading Determinate Nix builder configuration..." >&2
        /bin/launchctl kickstart -k system/systems.determinate.nix-daemon
        nix_daemon_ready=0
        # A cold Determinate daemon can take several seconds to accept the
        # first client after kickstart, especially on Clio.
        for _ in {1..6}; do
          if ${pkgs.coreutils}/bin/timeout --signal=KILL 5s \
            ${config.nix.package}/bin/nix store info --store daemon >/dev/null 2>&1; then
            nix_daemon_ready=1
            break
          fi
          /bin/sleep 0.25
        done
        if (( ! nix_daemon_ready )); then
          echo "Determinate Nix daemon did not become ready" >&2
          exit 1
        fi
      fi
    ''
    + lib.optionalString config.johnw.host.isHera ''
      # Hera hosts LLM services continuously. Reapply sleep=0 on each
      # activation; disksleep and displaysleep remain user-managed.
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
        orientation = if config.johnw.host.isClio then "right" else "left";
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
