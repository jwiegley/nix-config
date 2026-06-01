{
  pkgs,
  lib,
  config,
  hostname,
  vars,
  ...
}:
let
  inherit (vars) isDarwin identityDir;
in
{
  home.activation.createSshSocketDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "${config.home.homeDirectory}/.ssh/sockets"
    run chmod 700 "${config.home.homeDirectory}/.ssh/sockets"
  '';

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    settings =
      let
        withIdentity =
          attrs:
          attrs
          // {
            IdentityFile = "${identityDir}/id_${hostname}";
            IdentitiesOnly = true;
          };

        controlMastered =
          attrs:
          attrs
          // {
            ControlMaster = "auto";
            # %C is a SHA-1 hash of %l%h%p%r (40 hex chars). Using the literal
            # %h hostname overflows macOS's 104-byte unix-domain-socket limit
            # for hosts with long FQDNs (e.g. ec2-...compute.amazonaws.com)
            # once OpenSSH appends its random temp-file suffix.
            ControlPath = "${config.home.homeDirectory}/.ssh/sockets/%C";
            ControlPersist = "1800";
          };

        _matchHost = host: hostAddr: {
          hostname = hostAddr;
          match = ''
            host ${host} exec "${pkgs.unixtools.ping}/bin/ping -c1 -W50 -n -q ${hostAddr} > /dev/null 2>&1"
          '';
        };

        onHost =
          proxyJump: hostAddr:
          {
            HostName = hostAddr;
          }
          // lib.optionalAttrs (hostAddr != proxyJump) { ProxyJump = proxyJump; };

        localBind = here: there: {
          bind = {
            port = here;
          };
          host = {
            address = "127.0.0.1";
            port = there;
          };
        };
      in
      rec {
        "*" = {
          UserKnownHostsFile = "${config.xdg.configHome}/ssh/known_hosts";
          HashKnownHosts = true;
          ServerAliveInterval = 60;
          ForwardAgent = false;

          StrictHostKeyChecking = "yes";
          VerifyHostKeyDNS = "yes";
        }
        // lib.optionalAttrs isDarwin {
          IgnoreUnknown = "UseKeychain";
          UseKeychain = "yes";
          AddKeysToAgent = "yes";
        };

        # Hera

        hera = {
          HostName = "hera.lan";
          Compression = false;
          ForwardAgent = true;
        };

        mssql = onHost "hera" "192.168.64.3";
        deimos = onHost "hera" "192.168.221.128";
        simon = onHost "hera" "172.16.194.158";

        minerva = {
          HostName = "192.168.199.128";
          Compression = false;
        };

        # Clio

        clio = withIdentity {
          HostName = "clio.lan";
          Compression = false;
          ForwardAgent = true;
        };

        neso = withIdentity (onHost "clio" "192.168.100.130");

        # Vulcan

        vulcan_wifi = lib.hm.dag.entryBefore [ "vulcan_ethernet" ] (
          controlMastered (withIdentity {
            HostName = "192.168.3.16";
            Compression = false;

            ForwardAgent = true;

            ServerAliveInterval = 30;
            ServerAliveCountMax = 6;
            TCPKeepAlive = true;

            RemoteForward = [ (localBind 8317 8317) ];

            Match = ''
              host vulcan exec "${pkgs.bash}/bin/bash -c '[[ $(${pkgs.my-scripts}/bin/ipaddr bridge0) == 192.168.1.5 ]]'"
            '';
          })
        );

        vulcan_ethernet = controlMastered (withIdentity {
          HostName = "192.168.1.2";
          Compression = false;
          ForwardAgent = true;

          ServerAliveInterval = 30;
          ServerAliveCountMax = 6;
          TCPKeepAlive = true;

          RemoteForward = [ (localBind 8317 8317) ];
        });

        gitea = controlMastered (withIdentity {
          User = "gitea";
          HostName = if hostname == "vulcan" then "localhost" else "192.168.1.2";
          Port = 2222;
          Compression = false;
        });

        # Council

        "srp vps" = controlMastered {
          User = "johnw";
          HostName = "vps-b30dd5a8.vps.ovh.ca";
        };

        # Work

        ghpos = {
          User = "git";
          HostName = "github.com";
          IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
          IdentitiesOnly = true;

          ControlMaster = "no";
          ControlPath = "none";
        };

        ghai = {
          User = "git";
          HostName = "github.com";
          IdentityFile = "${config.xdg.configHome}/ssh/id_git-ai";
          IdentitiesOnly = true;

          ControlMaster = "no";
          ControlPath = "none";
        };

        positron = controlMastered {
          header = "Host pos andoria andoria-* delphi-* agentsrv labmgr sw-dev-01";
          User = "jwiegley";
          IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
          IdentitiesOnly = true;
        };

        "pos andoria" = controlMastered {
          User = "jwiegley";
          HostName = "andoria-08";
          IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
          IdentitiesOnly = true;
        };

        dev = controlMastered {
          User = "jwiegley";
          HostName = "sw-dev-01";
          IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
          IdentitiesOnly = true;
        };

        git-ai = controlMastered {
          HostName = "ec2-3-134-98-233.us-east-2.compute.amazonaws.com";
          User = "ubuntu";
          IdentityFile = "${config.xdg.configHome}/ssh/id_git-ai";
          IdentitiesOnly = true;
        };

        # Other servers

        router = withIdentity {
          HostName = "192.168.1.1";
          Compression = false;
        };

        asus1 = {
          HostName = "asus-bq16-pro-ap.lan";
          Port = 2204;
          User = "router";
          Compression = false;
        };
        asus2 = {
          HostName = "asus-bq16-pro-node.lan";
          Port = 2204;
          User = "router";
          Compression = false;
        };

        elpa = {
          HostName = "elpa.gnu.org";
          User = "root";
        };
        savannah.HostName = "git.sv.gnu.org";
        fencepost.HostName = "fencepost.gnu.org";

        savannah_gnu_org = withIdentity {
          header = "Host git.savannah.gnu.org git.sv.gnu.org git.savannah.nongnu.org git.sv.nongnu.org";
        };

        "*haskell.org" = {
          User = "root";
          IdentityFile = "${config.xdg.configHome}/ssh/id_haskell";
          IdentitiesOnly = true;
        };
        mail.HostName = "mail.haskell.org";

        "hf.co" = withIdentity {
          User = "git";
        };
      };
  };
}
