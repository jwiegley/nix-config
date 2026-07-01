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
      config
      hostname
      inputs
      ;
  };

  isHera = hostname == "hera";
  isAndoria = hostname == "andoria-08";
  isPositronSyncHost = isHera || isAndoria;

  heraDeviceId = "BZLR7L3-232RGLB-HWRZNFV-W3IPNB2-NRXL4XE-ZTV2IXC-5DBDPH5-NLPYPQT";
  andoriaDeviceId = "7QZW6HH-7XS3VJ5-YUOA4IU-AMTL2GY-FZFET4D-ADEJVHG-34QXSQU-45GEZQ5";

  folderId = "positron-home";
  heraTailscaleIP = "100.120.206.121";
  andoriaTailscaleIP = "100.85.190.60";
  versionsPath = "${config.xdg.stateHome}/syncthing/versions/${folderId}";

  positronIgnore = ''
    # Global pushme ignore list (~/.config/ignore.lst), translated from rsync
    # filter syntax for Syncthing's per-folder .stignore syntax.
    .DS_Store
    .cache
    .hoogle
    .localized
    /.AppleDB
    /.AppleDesktop
    /.AppleDouble
    /.Caches
    /.DocumentRevisions-V100
    /.Spotlight-V100
    /.TemporaryItems
    .Trash
    .Trashes
    /.VolumeIcon.icns
    /.apdisk
    /.bzvol
    /.com.apple.timemachine.supported
    /.fseventsd
    /.zfs
    /Network Trash Folder
    /Temporary Items
    /lost+found
    _cache

    # pushme Filters.srcFilters from ~/.config/pushme/config.yaml.
    *.agdai
    *.d
    *.glob
    *.hi
    *.o
    *.vio
    *.viok
    *.vios
    *.vo
    *.vok
    *.vos
    *~
    .*.aux
    .*.cache
    .autoagent
    .bun
    .cabal*
    .cache
    .cargo
    .cargo-home
    .direnv
    .envrc
    .ghc.*
    .lake
    .tmp
    .vagrant
    .venv
    MAlonzo
    Makefile.coq
    Makefile.coq.conf
    bash_snapshots
    build
    build-debug
    cabal.project.local*
    dist
    dist-newstyle
    gen
    node_modules
    result
    result-*
    target

    # pushme filesets/work_positron.yaml Common.ExtraFilters.
    /*-tmp
    /.claude
    /.codex
    /.local/lib
    /.local/share/cargo
    /.local/share/rustup
    /.local/share/uv
    /.local/state
    /go

    # Syncthing-local state. These are not part of the payload and must not
    # feed back into the folder being synchronized.
    /.config/syncthing
    /.stversions
  '';
in
{
  home.file = lib.mkIf isPositronSyncHost {
    ${if isHera then "work/positron/.stignore" else ".stignore"}.text = positronIgnore;
  };

  services.syncthing = lib.mkIf isPositronSyncHost {
    enable = true;

    settings = {
      devices = lib.mkMerge [
        (lib.optionalAttrs isHera {
          andoria = {
            id = andoriaDeviceId;
            addresses = [ "tcp://${andoriaTailscaleIP}:22000" ];
          };
        })
        (lib.optionalAttrs isAndoria {
          hera = {
            id = heraDeviceId;
            addresses = [ "tcp://${heraTailscaleIP}:22000" ];
          };
        })
      ];

      folders.${folderId} = {
        path = if isHera then "${vars.home}/work/positron" else vars.home;
        label = "Positron Home";
        devices = [ (if isHera then "andoria" else "hera") ];

        # Start in the same effective direction as pushme's current
        # work/positron flow. Once the first full scan converges cleanly,
        # switch both ends to "sendreceive" for actual bidirectional sync.
        type = if isHera then "receiveonly" else "sendonly";

        rescanIntervalS = 3600;
        fsWatcherEnabled = true;
        ignorePerms = true;
        versioning = {
          type = "trashcan";
          params.cleanoutDays = "14";
          fsPath = versionsPath;
          fsType = "basic";
        };
      };
    }
    // lib.optionalAttrs isAndoria {
      options = {
        listenAddresses = [ "tcp://${andoriaTailscaleIP}:22000" ];
        globalAnnounceEnabled = false;
        relaysEnabled = false;
        natEnabled = false;
        localAnnounceEnabled = false;
        urAccepted = -1;
        crashReportingEnabled = false;
      };
    };
  };
}
