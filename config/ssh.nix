{
  pkgs,
  lib,
  config,
  hostname,
  inputs,
  ...
}:
let
  vars = import ./vars.nix {
    inherit
      pkgs
      lib
      config
      hostname
      inputs
      ;
  };

  inherit (vars) isDarwin identityDir;

  tmpdir = "/tmp";
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks =
      let
        withIdentity =
          attrs:
          attrs
          // {
            identityFile = "${identityDir}/id_${hostname}";
            identitiesOnly = true;
          };

        controlMastered =
          attrs:
          attrs
          // {
            controlMaster = "auto";
            controlPath = "${tmpdir}/ssh-%u-%r@%h:%p";
            controlPersist = "1800";
          };

        onHost =
          proxyJump: hostAddr:
          {
            hostname = hostAddr;
          }
          // lib.optionalAttrs (hostAddr != proxyJump) { inherit proxyJump; };

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
        defaults = {
          host = "*";

          userKnownHostsFile = "${config.xdg.configHome}/ssh/known_hosts";
          hashKnownHosts = true;
          serverAliveInterval = 60;
          forwardAgent = false;

          extraOptions = {
            IgnoreUnknown = "UseKeychain";
          }
          // lib.optionalAttrs isDarwin {
            UseKeychain = "yes";
            AddKeysToAgent = "yes";
          };
        };

        # Hera

        hera = {
          hostname = "hera.lan";
          compression = false;
          forwardAgent = true;
        };

        mssql = onHost "hera" "192.168.64.3";
        deimos = onHost "hera" "192.168.221.128";
        simon = onHost "hera" "172.16.194.158";

        minerva = {
          hostname = "192.168.199.128";
          compression = false;
        };

        # Clio

        clio = withIdentity {
          hostname = "clio.lan";
          compression = false;
          forwardAgent = true;
        };

        neso = withIdentity (onHost "clio" "192.168.100.130");

        # Vulcan

        vulcan = controlMastered (withIdentity {
          hostname = "192.168.1.2";
          compression = false;
          forwardAgent = true;

          remoteForwards = [ (localBind 8317 8317) ];
        });

        gitea = controlMastered (withIdentity {
          user = "gitea";
          hostname = if hostname == "vulcan" then "localhost" else "192.168.1.2";
          port = 2222;
          compression = false;
        });

        # Council

        "srp vps" = controlMastered {
          user = "johnw";
          hostname = "vps-b30dd5a8.vps.ovh.ca";
        };

        # Work

        ghpos = {
          user = "git";
          hostname = "github.com";
          identityFile = "${config.xdg.configHome}/ssh/id_positron";
          identitiesOnly = true;

          controlMaster = "no";
          controlPath = "none";
        };

        positron = controlMastered {
          host = "pos andoria andoria-* delphi-* agentsrv labmgr";
          user = "jwiegley";
          identityFile = "${config.xdg.configHome}/ssh/id_positron";
          identitiesOnly = true;
        };

        "pos andoria" = controlMastered {
          user = "jwiegley";
          hostname = "andoria-08";
        };

        git-ai = controlMastered {
          host = "git-ai";
          user = "johnw";
          identityFile = "${config.xdg.configHome}/ssh/id_git-ai";
          identitiesOnly = true;
        };

        # Other servers

        router = withIdentity {
          hostname = "192.168.1.1";
          compression = false;
        };

        asus1 = {
          hostname = "asus-bq16-pro-ap.lan";
          port = 2204;
          user = "router";
          compression = false;
        };
        asus2 = {
          hostname = "asus-bq16-pro-node.lan";
          port = 2204;
          user = "router";
          compression = false;
        };

        elpa = {
          hostname = "elpa.gnu.org";
          user = "root";
        };
        savannah.hostname = "git.sv.gnu.org";
        fencepost.hostname = "fencepost.gnu.org";

        savannah_gnu_org = withIdentity {
          host = lib.concatStringsSep " " [
            "git.savannah.gnu.org"
            "git.sv.gnu.org"
            "git.savannah.nongnu.org"
            "git.sv.nongnu.org"
          ];
        };

        haskell_org = {
          host = "*haskell.org";
          user = "root";
          identityFile = "${config.xdg.configHome}/ssh/id_haskell";
          identitiesOnly = true;
        };
        mail.hostname = "mail.haskell.org";

        hf = withIdentity {
          host = "hf.co";
          user = "git";
        };
      };
  };
}
