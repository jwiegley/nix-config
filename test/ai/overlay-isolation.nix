{ pkgs, configured }:

let
  inherit (pkgs) lib;
  topLevel = [
    "ntp"
    "aprutil"
    "libcdio-paranoia"
    "folly"
    "fizz"
    "mvfst"
    "wangle"
    "fbthrift"
    "fb303"
    "edencommon"
    "watchman"
    "mesa"
    "xorg-server"
    "xquartz"
    "rclone"
    "nixos-render-docs"
    "libvirt"
    "contacts"
    "caligula"
    "spotify-player"
    "poppler"
    "prometheus-node-exporter"
    "gnupg"
    "zsh"
    "samba"
    "direnv"
    "squashfsTools"
    "z3"
    "srm"
    "kvazaar"
    "opencv4"
    "chromaprint"
    "openmpi"
    "pmix"
    "graphite-cli"
  ];
  python = [
    "av"
    "openai-whisper"
    "fsspec"
    "mirakuru"
  ];
  availableInBoth =
    left: right: name:
    builtins.hasAttr name left
    && builtins.hasAttr name right
    && lib.meta.availableOn pkgs.stdenv.hostPlatform left.${name}
    && lib.meta.availableOn configured.stdenv.hostPlatform right.${name};
  comparableTop = lib.filter (availableInBoth pkgs configured) topLevel;
  comparablePython = lib.filter (availableInBoth pkgs.python3Packages configured.python3Packages) python;
  changedTop = lib.filter (name: pkgs.${name}.drvPath != configured.${name}.drvPath) comparableTop;
  changedPython = lib.filter (
    name: pkgs.python3Packages.${name}.drvPath != configured.python3Packages.${name}.drvPath
  ) comparablePython;
in
assert
  changedTop == [ ]
  || throw "Darwin-only top-level overrides active on Linux: ${builtins.toJSON changedTop}";
assert
  changedPython == [ ]
  || throw "Darwin-only Python overrides active on Linux: ${builtins.toJSON changedPython}";
assert
  (configured.python3Packages.imageio.disabledTests or [ ])
  == (pkgs.python3Packages.imageio.disabledTests or [ ])
  || throw "Darwin-only imageio test suppression active on Linux";
assert
  (configured.python3Packages.gradio.doInstallCheck or false)
  == (pkgs.python3Packages.gradio.doInstallCheck or false)
  || throw "Darwin-only Gradio install-check suppression active on Linux";
assert
  !(configured ? inputs) || throw "overlay composition leaked flake inputs through pkgs.inputs";
pkgs.runCommand "darwin-overrides-inactive" { } "touch $out"
