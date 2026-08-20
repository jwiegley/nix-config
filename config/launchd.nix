{
  pkgs,
  lib,
  config,
  ...
}:

let
  home = "/Users/johnw";
  xdg_configHome = "${home}/.config";
  xdg_cacheHome = "${home}/.cache";
  recordingCaBundle = "${pkgs.ca-bundle-with-vulcan or pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  runsEternalTerminal = config.johnw.host.isDarwinWorkstation;
  serviceLaunchers = import ./launchd-service-launchers.nix { inherit lib pkgs; };
  mssqlImageSource = (import ../packages/source-catalog.nix "tools").mssql-server-image;
  mssqlManifestPrefix = "https://mcr.microsoft.com/v2/mssql/server/manifests/";
  mssqlImageDigest =
    assert mssqlImageSource.source.fetcher == "fetchurl";
    assert mssqlImageSource.source.args.url == mssqlImageSource.source.url;
    assert lib.hasPrefix mssqlManifestPrefix mssqlImageSource.source.url;
    lib.removePrefix mssqlManifestPrefix mssqlImageSource.source.url;
  mssqlImageReference =
    assert
      mssqlImageSource.source.args.hash == builtins.convertHash {
        hash = mssqlImageDigest;
        hashAlgo = "sha256";
        toHashFormat = "sri";
      };
    "mcr.microsoft.com/mssql/server@${mssqlImageDigest}";
  mssqlServerLauncher = serviceLaunchers.mssql {
    credentialDirectory = "/Library/Application Support/nix-config/mssql";
    credentialOwnerUid = 0;
    credentialTrustRoot = "/";
    dataDirectory = "/private/var/lib/nix-config/mssql-data/data";
    dataOwner = "johnw";
    dataOwnerUid = null;
    dataParentOwnerUid = 0;
    dataTrustRoot = "/";
    imageReference = mssqlImageReference;
  };
  vlcApp = pkgs.callPackage ../packages/vlc-bin.nix { };
  vlcRuntimeHome = pkgs.runCommand "vlc-telnet-home" { } ''
    mkdir -p "$out/Library/Application Support/org.videolan.vlc"
  '';
  vlcTelnetLauncher = serviceLaunchers.vlcTelnet {
    account = "johnw";
    inherit home;
    keychainService = "nix-config.vlc-telnet";
    port = 4212;
    vlcBin = "${vlcApp}/Applications/VLC.app/Contents/MacOS/VLC";
    vlcHome = "${vlcRuntimeHome}";
  };
  omlxProxy = config.johnw.omlxProxy;
  eternalTerminalConfig = pkgs.writeText "et.cfg" ''
    ; et.cfg : Config file for Eternal Terminal
    ;

    [Networking]
    port = 2022

    [Debug]
    verbose = 0
    silent = 0
    logsize = 20971520
    telemetry = false
    logdirectory = /Library/Logs/EternalTerminal
  '';
  spotlightTransientDirs = [
    "${home}/.cache"
    "${home}/.cache/cargo"
    "${home}/.cache/sccache"
    "${home}/.cargo"
    "${home}/.config/codex/.tmp"
    "${home}/.local/share/cargo"
    "${home}/.local/share/rustup"
    "${home}/.rustup"
    "${home}/.sccache"
    "${home}/Products"
    "${home}/Library/Caches"
    "${home}/Library/Developer/CoreSimulator/Caches"
    "${home}/Library/Developer/Xcode/DerivedData"
  ];
  spotlightTransientRoots = [
    "${home}/.config"
    "${home}/doc"
    "${home}/hera"
    "${home}/src"
    "${home}/work"
  ];
  spotlightTransientNames = [
    ".cache"
    ".*.cache"
    ".cabal*"
    ".cargo-home"
    ".direnv"
    ".devenv"
    ".git"
    ".gradle"
    ".ghc.*"
    ".hg"
    ".jj"
    ".lake"
    ".mypy_cache"
    ".next"
    ".nox"
    ".pytest_cache"
    ".ruff_cache"
    ".svelte-kit"
    ".swiftpm"
    ".terraform"
    ".tmp"
    ".tox"
    ".vagrant"
    ".venv"
    ".build"
    "__pycache__"
    "Pods"
    "MAlonzo"
    "bash_snapshots"
    "bazel-*"
    "build"
    "build-debug"
    "coverage"
    "dist"
    "dist-newstyle"
    "htmlcov"
    "node_modules"
    "result"
    "result-*"
    "target"
    "target-*"
    "venv"
  ];
  spotlightTransientFindExpr = lib.concatMapStringsSep " -o " (
    name: "-name ${lib.escapeShellArg name}"
  ) spotlightTransientNames;
  spotlightTransientExclusions = pkgs.writeShellScript "spotlight-transient-exclusions" ''
    set -eu

    mark_dir() {
      dir="$1"
      [ -d "$dir" ] || return 0

      marker="$dir/.metadata_never_index"
      if [ ! -e "$marker" ]; then
        : > "$marker"
        echo "$(/bin/date '+%Y-%m-%d %H:%M:%S') marked $dir"
      fi
    }

    mark_cargo_target() {
      target="$1"
      mark_dir "$target"

      for dir in "$target/doc" "$target/package" "$target/tmp" "$target/.cargo-home"; do
        mark_dir "$dir"
      done

      /usr/bin/find "$target" -xdev -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null |
        while IFS= read -r profile_dir; do
          mark_dir "$profile_dir"
          for dir in \
            "$profile_dir/.fingerprint" \
            "$profile_dir/build" \
            "$profile_dir/deps" \
            "$profile_dir/examples" \
            "$profile_dir/incremental" \
            "$profile_dir/native"; do
            mark_dir "$dir"
          done
        done
    }

    for dir in ${lib.escapeShellArgs spotlightTransientDirs}; do
      mark_dir "$dir"
    done

    for root in ${lib.escapeShellArgs spotlightTransientRoots}; do
      [ -d "$root" ] || continue

      /usr/bin/find "$root" -xdev -type d \( ${spotlightTransientFindExpr} \) -prune -print 2>/dev/null |
        while IFS= read -r dir; do
          case "''${dir##*/}" in
            target) mark_cargo_target "$dir" ;;
            *) mark_dir "$dir" ;;
          esac
        done
    done
  '';

in
{
  # Import the host capability option this module reads rather than relying on a
  # parent module's import list.
  imports = [
    ./host-options.nix
    ./omlx-proxy-boundary.nix
  ];

  launchd = {
    # System daemons run as background services
    daemons = {
      mssql-server = {
        serviceConfig = {
          EnvironmentVariables = {
            DOCKER_CONFIG = "/var/root/.docker";
            DOCKER_HOST = "unix:///var/run/docker.sock";
            HOME = "/var/root";
            LOGNAME = "root";
            PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
            USER = "root";
            ZDOTDIR = "/var/root";
          };
          ProgramArguments = [ "${mssqlServerLauncher}/bin/mssql-server-launcher" ];
          RunAtLoad = true;
          KeepAlive = false;
        };
      };
    }
    // lib.optionalAttrs runsEternalTerminal {
      eternal-terminal = {
        script = ''
          exec ${pkgs.eternal-terminal}/bin/etserver --cfgfile ${eternalTerminalConfig}
        '';
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = 30;
          SoftResourceLimits.NumberOfFiles = 4096;
          HardResourceLimits.NumberOfFiles = 4096;
          StandardOutPath = "/Library/Logs/eternal-terminal-launchd.log";
          StandardErrorPath = "/Library/Logs/eternal-terminal-launchd.log";
        };
      };
    }
    // lib.optionalAttrs config.johnw.host.isHera {
      nix-temproots-cleanup = {
        # Root discovery removes only unlocked stale temproot records (and
        # broken automatic GC-root links); it never deletes store contents.
        script = ''
          exec /nix/var/nix/profiles/default/bin/nix-store --gc --print-roots
        '';
        serviceConfig = {
          RunAtLoad = false;
          KeepAlive = false;
          StartCalendarInterval = {
            Hour = 4;
            Minute = 30;
          };
          Nice = 10;
          LowPriorityIO = true;
          LowPriorityBackgroundIO = true;
          ProcessType = "Background";
          StandardOutPath = "/dev/null";
          StandardErrorPath = "/dev/null";
        };
      };

      "sysctl-vram-limit" = {
        script = ''
          # This leaves 64 GB of working memory remaining
          # /usr/sbin/sysctl iogpu.wired_limit_mb=458752

          # This leaves 32 GiB outside the wired GPU allocation.
          /usr/sbin/sysctl iogpu.wired_limit_mb=491520
        '';
        serviceConfig.RunAtLoad = true;
      };
    };

    user.agents = {
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
          --listen "127.0.0.1:8080"         \
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
                listen ${lib.optionalString omlxProxy.enable "${omlxProxy.listenAddress}:"}8443 ssl;

                ssl_certificate /Users/johnw/hera/hera.lan.crt;
                ssl_certificate_key /Users/johnw/hera/hera.lan.key;
                ssl_protocols TLSv1.2 TLSv1.3;
                ssl_prefer_server_ciphers on;
                ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;

                access_log ${logDir}/access.log;

                ${lib.optionalString omlxProxy.enable ''
                  # Expose the loopback-only oMLX API only to explicitly
                  # allowed clients. oMLX validates the forwarded bearer
                  # credential itself.
                  location /v1/ {
                    ${lib.concatMapStringsSep "\n                  " (
                      source: "allow ${source};"
                    ) omlxProxy.allowedSources}
                    deny all;

                    client_max_body_size 20M;
                    proxy_pass http://127.0.0.1:8000;

                    proxy_set_header Authorization $http_authorization;
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;

                    proxy_connect_timeout 600;
                    proxy_send_timeout 600;
                    proxy_read_timeout 600;
                    send_timeout 600;
                  }
                ''}

                # Proxy all other requests to chat.vulcan.lan
                location / {
                  proxy_pass https://chat.vulcan.lan;
                  proxy_ssl_verify on;
                  proxy_ssl_trusted_certificate /Users/johnw/hera/vulcan-root-ca.crt;
                  proxy_ssl_server_name on;

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

      omlx = {
        script = "exec ${pkgs.omlx}/bin/omlx serve --host 127.0.0.1 --port 8000 --base-path /Users/johnw/.config/omlx/.omlx";
        serviceConfig = {
          RunAtLoad = true;
          # Restart on crash but not on clean exit, and throttle restarts so
          # a persistent startup failure (missing model, port in use) backs
          # off instead of spin-looping and flooding the log.
          KeepAlive.SuccessfulExit = false;
          ThrottleInterval = 30;
          StandardOutPath = "/Users/johnw/.local/share/omlx/logs/launchd.log";
          StandardErrorPath = "/Users/johnw/.local/share/omlx/logs/launchd.log";
        };
      };
    }
    // lib.optionalAttrs config.johnw.host.isHera {
      cleanup = {
        serviceConfig = {
          EnvironmentVariables.PYTHONPATH = "${pkgs.dirscan}/${pkgs.python3.sitePackages}";
          ProgramArguments = [
            "/usr/bin/python3"
            "${pkgs.dirscan}/bin/.cleanup-wrapped"
            "-u"
          ];
          StartInterval = 86400;
          RunAtLoad = false;
          StandardOutPath = "${home}/Library/Logs/cleanup.stdout.log";
          StandardErrorPath = "${home}/Library/Logs/cleanup.stderr.log";
        };
      };

      docker-desktop = {
        script = "/usr/bin/open -a /Applications/Docker.app";
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = false;
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
              -R 127.0.0.1:9222:127.0.0.1:9223
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
        serviceConfig = {
          EnvironmentVariables = {
            HOME = home;
            LOGNAME = "johnw";
            PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
            USER = "johnw";
          };
          ProgramArguments = [ "${vlcTelnetLauncher}/bin/vlc-telnet-launcher" ];
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = 30;
        };
      };

      spotlight-transient-exclusions = {
        script = "exec ${spotlightTransientExclusions}";
        serviceConfig = {
          RunAtLoad = true;
          StartInterval = 3600;
          LowPriorityIO = true;
          LowPriorityBackgroundIO = true;
          ProcessType = "Background";
          StandardOutPath = "${home}/Library/Logs/spotlight-transient-exclusions.log";
          StandardErrorPath = "${home}/Library/Logs/spotlight-transient-exclusions.log";
        };
      };
    }
    # These agents shell out to pkgs.my-scripts, which exists only where the
    # flake provides a `scripts` input. Guard the whole set so a Darwin consumer
    # without that input still evaluates (mirrors the config/ssh.nix guard).
    // lib.optionalAttrs (config.johnw.host.isHera && (pkgs ? my-scripts)) {

      push-tank = {
        script = ''
          timestamp=$(/bin/date '+%Y-%m-%d %H:%M:%S %Z') || exit
          printf '\n----- push tank: %s -----\n' "$timestamp" || exit
          exec ${pkgs.my-scripts}/bin/push tank
        '';
        serviceConfig = {
          EnvironmentVariables = {
            HOME = home;
            LOGNAME = "johnw";
            PATH = "${
              lib.makeBinPath [
                pkgs.bash
                pkgs.my-scripts
                pkgs.nix-scripts
                pkgs.openssh
                pkgs.rsync
              ]
            }:/etc/profiles/per-user/johnw/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin";
            SSH_AUTH_SOCK = "${xdg_configHome}/gnupg/S.gpg-agent.ssh";
            USER = "johnw";
          };
          RunAtLoad = false;
          StartInterval = 3600;
          StandardOutPath = "${home}/Library/Logs/push-tank.log";
          StandardErrorPath = "${home}/Library/Logs/push-tank.log";
        };
      };

      flatten-recordings = {
        script = ''
          export PATH="${pkgs.my-scripts}/bin:${pkgs.fswatch}/bin:/etc/profiles/per-user/johnw/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
          export SSL_CERT_FILE="${recordingCaBundle}"

          # Sweep anything that accumulated while we were not running.
          ${pkgs.my-scripts}/bin/flatten-recordings || true

          # Coalesce recursive events before running the serialized worker.
          ${pkgs.fswatch}/bin/fswatch --recursive --latency 5 \
                --event=Created --event=Updated \
                --event=MovedTo --event=Renamed \
                "${home}/Recordings" |
            while read -r _; do
              ${pkgs.my-scripts}/bin/flatten-recordings || true
            done
        '';
        serviceConfig = {
          RunAtLoad = true; # Initial sweep at login.
          KeepAlive = true; # Relaunch the fswatch loop if it ever exits.
          # Prevent launchd from throttling the watcher's I/O while the display
          # is off.
          LowPriorityIO = false;
          LowPriorityBackgroundIO = false;
          ProcessType = "Standard";
          StandardOutPath = "${home}/Library/Logs/flatten-recordings.log";
          StandardErrorPath = "${home}/Library/Logs/flatten-recordings.log";
        };
      };

      # Periodically cover watcher misses; the worker lock handles overlap with
      # event-triggered runs.
      flatten-recordings-sweep = {
        script = ''
          export PATH="${pkgs.my-scripts}/bin:/etc/profiles/per-user/johnw/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
          export SSL_CERT_FILE="${recordingCaBundle}"
          ${pkgs.my-scripts}/bin/flatten-recordings || true
        '';
        serviceConfig = {
          RunAtLoad = true; # Sweep once at login/activation.
          StartInterval = 900; # And every 15 minutes thereafter.
          # Match the fswatch agent's unthrottled I/O policy.
          LowPriorityIO = false;
          LowPriorityBackgroundIO = false;
          ProcessType = "Standard";
          StandardOutPath = "${home}/Library/Logs/flatten-recordings.log";
          StandardErrorPath = "${home}/Library/Logs/flatten-recordings.log";
        };
      };
    };
  };
}
