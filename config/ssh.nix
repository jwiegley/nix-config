args@{
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
  hostRegistry = args.hostRegistry or (import ./hosts.nix);
  inherit (hostRegistry) hosts networkPeers;

  # The authored SSH configuration, in home-manager's master
  # `programs.ssh.settings` (RFC42) shape: attribute names are `Host` patterns
  # (or a literal `header`), and each value is an attrset keyed by PascalCase
  # ssh_config directive names. Shared machine identities and addresses come
  # from the host registry. This connection policy is rendered unchanged on
  # home-manager versions that ship
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
        HostName = hosts.hera.dnsName;
        Compression = false;
        ForwardAgent = true;
      };

      mssql = onHost networkPeers.mssql.via networkPeers.mssql.ipv4.ssh;
      deimos = onHost networkPeers.deimos.via networkPeers.deimos.ipv4.ssh;
      simon = onHost networkPeers.simon.via networkPeers.simon.ipv4.ssh;

      minerva = {
        HostName = networkPeers.minerva.ipv4.ssh;
        Compression = false;
      };

      clio = withIdentity {
        HostName = hosts.clio.dnsName;
        Compression = false;
        ForwardAgent = true;
      };

      neso = withIdentity (onHost networkPeers.neso.via networkPeers.neso.ipv4.ssh);

      vulcan = controlMastered (withIdentity {
        HostName = hosts.vulcan.ipv4.lan;
        Compression = false;
        ForwardAgent = true;

        ServerAliveInterval = 30;
        ServerAliveCountMax = 6;
        TCPKeepAlive = true;
      });

      gitea = controlMastered (withIdentity {
        User = "gitea";
        HostName = if config.johnw.host.isVulcan then "localhost" else hosts.vulcan.ipv4.lan;
        Port = 2222;
        Compression = false;
      });

      pi = {
        User = "pi";
        HostName = "raspberrypi.lan";
        Compression = false;
        # BatchMode = false;
        # KbdInteractiveAuthentication = true;
        # PasswordAuthentication = true;
        # PreferredAuthentications = "password";
      };

      "srp vps" = controlMastered {
        User = hosts.vps.username;
        HostName = hosts.vps.dnsName;
      };

      ghpos = {
        User = "git";
        HostName = networkPeers.github.dnsName;
        IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
        IdentitiesOnly = true;

        ControlMaster = "no";
        ControlPath = "none";
      };

      positron =
        controlMastered {
          header = "Host andoria-* delphi-* sw-dev-* agentsrv labmgr";
          User = hosts.andoria.username;
          IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
          IdentitiesOnly = true;
          ForwardAgent = true;
        }
        // lib.optionalAttrs config.johnw.host.isClio {
          ProxyJump = "${hosts.hera.username}@hera";
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
        User = hosts.andoria-08.username;
        HostName = hosts.andoria-08.dnsName;
        IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
        IdentitiesOnly = true;
        ForwardAgent = true;
      };

      "gpu gpu-server" = controlMastered {
        User = hosts.gpu-server.username;
        HostName = hosts.gpu-server.dnsName;
        IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
        IdentitiesOnly = true;
        ForwardAgent = true;
      };

      dev = controlMastered {
        User = hosts.andoria.username;
        HostName = networkPeers.workDev.dnsName;
        IdentityFile = "${config.xdg.configHome}/ssh/id_positron";
        IdentitiesOnly = true;
      };

      ghai = {
        User = "git";
        HostName = networkPeers.github.dnsName;
        IdentityFile = "${config.xdg.configHome}/ssh/id_git-ai";
        IdentitiesOnly = true;

        ControlMaster = "no";
        ControlPath = "none";
      };

      git-ai = controlMastered {
        HostName = hosts.git-ai.dnsName;
        User = hosts.git-ai.sshUser;
        IdentityFile = "${config.xdg.configHome}/ssh/id_git-ai";
        IdentitiesOnly = true;
      };

      router = withIdentity {
        HostName = networkPeers.router.ipv4.lan;
        Compression = false;
      };

      asus1 = {
        HostName = networkPeers.asus1.dnsName;
        Port = networkPeers.asus1.sshPort;
        User = networkPeers.asus1.sshUser;
        Compression = false;
      };
      asus2 = {
        HostName = networkPeers.asus2.dnsName;
        Port = networkPeers.asus2.sshPort;
        User = networkPeers.asus2.sshUser;
        Compression = false;
      };

      elpa = {
        HostName = networkPeers.elpa.dnsName;
        User = "root";
      };
      savannah.HostName = networkPeers.savannah.dnsName;
      fencepost.HostName = networkPeers.fencepost.dnsName;

      savannah_gnu_org = withIdentity {
        header = "Host ${lib.concatStringsSep " " networkPeers.savannah.aliases}";
      };

      "*haskell.org" = {
        User = "root";
        IdentityFile = "${config.xdg.configHome}/ssh/id_haskell";
        IdentitiesOnly = true;
      };
      mail.HostName = networkPeers.haskellMail.dnsName;

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
        header = ''Match host vulcan exec "${pkgs.bash}/bin/bash -c '[[ $(${pkgs.my-scripts}/bin/ipaddr bridge0) == ${hosts.clio.ipv4.lan} ]]'"'';
        HostName = hosts.vulcan.ipv4.wifi;
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
