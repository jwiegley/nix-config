{
  pkgs,
  lib,
  hostname,
  ...
}:

let
  home = "/Users/johnw";
  xdg_configHome = "${home}/.config";
  xdg_cacheHome = "${home}/.cache";
  runsEternalTerminal = lib.elem hostname [
    "hera"
    "clio"
  ];
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

in
{
  launchd = {
    # System daemons run as background services
    daemons = {
      limits = {
        script = ''
          /bin/launchctl limit maxfiles 524288 524288
          /bin/launchctl limit maxproc 8192 8192
        '';
        serviceConfig.RunAtLoad = true;
        serviceConfig.KeepAlive = false;
      };

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
            -p 127.0.0.1:1433:1433 \
            -v ${home}/mssql:/var/opt/mssql \
            -e ACCEPT_EULA=Y \
            -e "MSSQL_SA_PASSWORD=$MSSQL_SA_PASSWORD" \
            mcr.microsoft.com/mssql/server:2022-latest
        '';
        serviceConfig.RunAtLoad = true;
        serviceConfig.KeepAlive = false;
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
        script = "exec ${pkgs.omlx}/bin/omlx serve --base-path /Users/johnw/.config/omlx/.omlx";
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
    // lib.optionalAttrs (hostname == "hera") {
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

      # Self-heal for SyncThing. SyncThing runs as the home-manager agent
      # `org.nix-community.home.syncthing` (services.syncthing in johnw.nix),
      # which KeepAlive=true keeps alive *once loaded*. But home-manager's
      # Darwin activation reloads a changed agent with `launchctl bootout`
      # followed by `launchctl bootstrap`, and it ignores a failed bootstrap
      # and continues — so a `u switch` that updates SyncThing can leave the
      # agent unloaded in *no* domain (observed 2026-06-25: a syncthing bump
      # booted out the running daemon and the re-bootstrap did not take,
      # leaving it down). KeepAlive cannot recover that because nothing is
      # loaded. This watchdog re-registers it. It targets gui/$uid to match
      # the current home-manager (which hard-codes the gui domain for agents).
      syncthing-watchdog = {
        script = ''
          label=org.nix-community.home.syncthing
          uid="$(/usr/bin/id -u)"
          plist="${home}/Library/LaunchAgents/$label.plist"

          if /bin/launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
            # Registered — ensure it is actually running (no-op if it already is).
            /bin/launchctl kickstart "gui/$uid/$label" >/dev/null 2>&1 || true
          elif [ -f "$plist" ]; then
            # Not registered: re-bootstrap it ourselves and note it in the log.
            echo "$(/bin/date '+%Y-%m-%d %H:%M:%S') re-bootstrapping $label into gui/$uid"
            /bin/launchctl bootstrap "gui/$uid" "$plist" || true
          fi
        '';
        serviceConfig = {
          RunAtLoad = true; # check immediately after login / activation
          StartInterval = 180; # and re-check every 3 minutes
          StandardOutPath = "${home}/Library/Logs/syncthing-watchdog.log";
          StandardErrorPath = "${home}/Library/Logs/syncthing-watchdog.log";
        };
      };

      docker-desktop = {
        script = "/usr/bin/open -a /Applications/Docker.app";
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

      autossh-andoria-syncthing = {
        script = ''
          export AUTOSSH_GATETIME=0
          export SSH_AUTH_SOCK="${xdg_configHome}/gnupg/S.gpg-agent.ssh"
          ${pkgs.autossh}/bin/autossh -M 0 -N andoria-08 \
              -o "ControlMaster=no"                       \
              -o "ControlPath=none"                       \
              -o "ServerAliveInterval=30"                 \
              -o "ServerAliveCountMax=3"                  \
              -o "ExitOnForwardFailure=yes"               \
              -L 127.0.0.1:22001:127.0.0.1:22000          \
              -R 127.0.0.1:22001:127.0.0.1:22000
        '';
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = 30;
          StandardOutPath = "${xdg_cacheHome}/autossh-andoria-syncthing.log";
          StandardErrorPath = "${xdg_cacheHome}/autossh-andoria-syncthing.log";
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
    }
    # `flatten-recordings` shells out to pkgs.my-scripts/bin/flatten-recordings,
    # which exists only where the flake provides a `scripts` input. Guard the
    # whole agent so a Darwin consumer without that input still evaluates
    # (mirrors the config/ssh.nix guard).
    // lib.optionalAttrs (pkgs ? my-scripts) {

      flatten-recordings = {
        script = ''
          export PATH="${pkgs.my-scripts}/bin:${pkgs.fswatch}/bin:/etc/profiles/per-user/johnw/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

          # Sweep anything that accumulated while we were not running.
          ${pkgs.my-scripts}/bin/flatten-recordings || true

          # Then react to filesystem changes under ~/Recordings instead of
          # polling every 15 minutes. --latency 5 coalesces bursts; the
          # script is idempotent and re-sweeps the whole directory on each
          # invocation, so an occasional duplicate event is harmless.
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
          # Without these two, launchd classifies the agent as background
          # work and throttles its I/O when the display is off — the cause
          # of the 2.4h stall on a 105 KB archive mv on 2026-05-22.
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
