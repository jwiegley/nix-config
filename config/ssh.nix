{
  pkgs,
  lib,
  config,
  options,
  hostname,
  vars,
  ...
}:
let
  inherit (vars) isDarwin identityDir;

  # The authored SSH configuration, in home-manager's master
  # `programs.ssh.settings` (RFC42) shape: attribute names are `Host` patterns
  # (or a literal `header`), and each value is an attrset keyed by PascalCase
  # ssh_config directive names. This attrset is the single source of truth for
  # every host and is rendered UNCHANGED on any home-manager that ships
  # `settings` (see the capability gate below).
  sshSettings =
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
          ControlPath = "${config.home.homeDirectory}/.ssh/sockets/%C";
          ControlPersist = "1800";
        };

      onHost =
        proxyJump: hostAddr:
        {
          HostName = hostAddr;
        }
        // lib.optionalAttrs (hostAddr != proxyJump) { ProxyJump = proxyJump; };

    in
    rec {
      "*" = {
        UserKnownHostsFile = "${config.xdg.configHome}/ssh/known_hosts";
        HashKnownHosts = true;
        ServerAliveInterval = 60;
        ForwardAgent = false;
        BatchMode = true;
        KbdInteractiveAuthentication = false;
        PasswordAuthentication = false;

        StrictHostKeyChecking = "yes";
        VerifyHostKeyDNS = "yes";
      }
      // lib.optionalAttrs isDarwin {
        IgnoreUnknown = "UseKeychain";
        UseKeychain = "yes";
        AddKeysToAgent = "yes";
      };

      hera = withIdentity {
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

      clio = withIdentity {
        HostName = "clio.lan";
        Compression = false;
        ForwardAgent = true;
      };

      neso = withIdentity (onHost "clio" "192.168.100.130");

      vulcan = controlMastered (withIdentity {
        HostName = "192.168.1.2";
        Compression = false;
        ForwardAgent = true;

        ServerAliveInterval = 30;
        ServerAliveCountMax = 6;
        TCPKeepAlive = true;
      });

      gitea = controlMastered (withIdentity {
        User = "gitea";
        HostName = if config.johnw.host.isVulcan then "localhost" else "192.168.1.2";
        Port = 2222;
        Compression = false;
      });

      "srp vps" = controlMastered {
        User = "johnw";
        HostName = "vps-b30dd5a8.vps.ovh.ca";
      };

      ghpos = {
        User = "git";
        HostName = "github.com";
        IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
        IdentitiesOnly = true;

        ControlMaster = "no";
        ControlPath = "none";
      };

      positron =
        controlMastered {
          header = "Host andoria-* delphi-* sw-dev-* agentsrv labmgr";
          User = "jwiegley";
          IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
          IdentitiesOnly = true;
          ForwardAgent = true;
        }
        // lib.optionalAttrs config.johnw.host.isClio {
          ProxyJump = "johnw@hera";
        };

      positron-api = controlMastered {
        User = "positron";
        IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
        IdentitiesOnly = true;
      };

      atlas = controlMastered {
        header = "Host atlas-*";
        User = "positron";
        IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
        IdentitiesOnly = true;
        ProxyJump = "positron-api";
      };

      "pos andoria" = controlMastered {
        User = "jwiegley";
        HostName = "andoria-08";
        IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
        IdentitiesOnly = true;
        ForwardAgent = true;
      };

      "gpu gpu-server" = controlMastered {
        User = "jwiegley";
        HostName = "gpu-server";
        IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
        IdentitiesOnly = true;
        ForwardAgent = true;
      };

      dev = controlMastered {
        User = "jwiegley";
        HostName = "sw-dev-01";
        IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
        IdentitiesOnly = true;
      };

      ghai = {
        User = "git";
        HostName = "github.com";
        IdentityFile = "${config.xdg.configHome}/ssh/id_git-ai";
        IdentitiesOnly = true;

        ControlMaster = "no";
        ControlPath = "none";
      };

      git-ai = controlMastered {
        HostName = "ec2-3-134-98-233.us-east-2.compute.amazonaws.com";
        User = "ubuntu";
        IdentityFile = "${config.xdg.configHome}/ssh/id_git-ai";
        IdentitiesOnly = true;
      };

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
    }
    // lib.optionalAttrs config.johnw.host.isDarwinWorkstation {
      "github.com" = {
        User = "git";
        IdentityAgent = "${config.xdg.configHome}/gnupg/S.gpg-agent.ssh";
      };
    }
    // lib.optionalAttrs (pkgs ? my-scripts) {
      vulcan_wifi = lib.hm.dag.entryBefore [ "vulcan" ] {
        header = ''Match host vulcan exec "${pkgs.bash}/bin/bash -c '[[ $(${pkgs.my-scripts}/bin/ipaddr bridge0) == 192.168.1.5 ]]'"'';
        HostName = "192.168.3.16";
      };
    };

  # release-25.11 compatibility shim, promoted from vulcan's
  # ssh-settings-compat.nix. Home Manager release-25.11 ships only
  # `programs.ssh.matchBlocks` (camelCase options plus a freeform
  # `extraOptions = attrsOf str`) and has no `settings` option, so the authored
  # blocks above are translated into `matchBlocks` when the library in scope
  # lacks `settings`. On master this branch is never taken.
  structuredOption = {
    RemoteForward = "remoteForwards";
    LocalForward = "localForwards";
    DynamicForward = "dynamicForwards";
    IdentityFile = "identityFile";
    IdentityAgent = "identityAgent";
    CertificateFile = "certificateFile";
    SendEnv = "sendEnv";
  };
  listOfStrOption = [
    "identityFile"
    "identityAgent"
    "certificateFile"
    "sendEnv"
  ];

  scalarToStr = v: if lib.isBool v then (if v then "yes" else "no") else toString v;

  isDagEntry = v: lib.isAttrs v && v ? data && v ? after && v ? before;

  mkBlock =
    pattern: attrs:
    let
      header = attrs.header or null;
      hostMatch =
        if header == null then
          {
            host = pattern;
            match = null;
          }
        else if lib.hasPrefix "Match " header then
          {
            host = null;
            match = lib.removePrefix "Match " header;
          }
        else if lib.hasPrefix "Host " header then
          {
            host = lib.removePrefix "Host " header;
            match = null;
          }
        else
          {
            host = header;
            match = null;
          };

      directives = removeAttrs attrs [ "header" ];
      structured = lib.filterAttrs (k: _v: builtins.hasAttr k structuredOption) directives;
      scalars = lib.filterAttrs (k: v: !(builtins.hasAttr k structuredOption) && v != null) directives;

      structuredOpts = lib.mapAttrs' (
        k: v:
        let
          opt = structuredOption.${k};
        in
        lib.nameValuePair opt (
          if lib.elem opt listOfStrOption then
            (if lib.isList v then map toString v else [ (toString v) ])
          else
            v
        )
      ) structured;
    in
    {
      inherit (hostMatch) host match;
      extraOptions = lib.mapAttrs (_k: scalarToStr) scalars;
    }
    // structuredOpts;

  toMatchBlock =
    pattern: raw:
    if isDagEntry raw then
      # `entryBetween = before: after: data` in home-manager's DAG library, so
      # `before` and `after` must be passed in that order. Vulcan's original
      # ssh-settings-compat.nix passed them reversed, which silently inverted
      # every DAG-ordered block (e.g. the `vulcan_wifi` Match block, authored
      # `entryBefore [ "vulcan" ]`, rendered AFTER `Host vulcan` and was
      # defeated by ssh's first-match-wins). Ordering now matches master.
      lib.hm.dag.entryBetween (raw.before or [ ]) (raw.after or [ ]) (mkBlock pattern raw.data)
    else
      mkBlock pattern raw;

  toMatchBlocks = settings: lib.mapAttrs toMatchBlock settings;

  # Capability gate: decide the API from the home-manager LIBRARY in scope, not
  # from a hostname. Master declares `programs.ssh.settings`; release-25.11 does
  # not. A hostname check would reproduce the very class of skew this removes.
  hasSettings = options.programs.ssh ? settings;
in
{
  # Import the host capability option this module reads rather than relying on a
  # parent module's import list.
  imports = [ ./host-options.nix ];

  home.activation.createSshSocketDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "${config.home.homeDirectory}/.ssh/sockets"
    run chmod 700 "${config.home.homeDirectory}/.ssh/sockets"
  '';

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
  }
  // (
    if hasSettings then
      {
        settings = sshSettings;
      }
    else
      {
        matchBlocks = toMatchBlocks sshSettings;
      }
  );
}
