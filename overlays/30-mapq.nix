# overlays/30-mapq.nix
# Purpose: Apple Maps query CLI tool for OpenClaw
# Dependencies: macOS system Swift compiler and MapKit framework
# Packages: mapq
final: prev: {

  mapq = prev.stdenv.mkDerivation {
    name = "mapq-1.0.0";
    src = ../pkgs/mapq;

    # Only meaningful on Darwin
    meta.platforms = prev.lib.platforms.darwin;

    # Allow access to macOS system Swift and Xcode frameworks
    # Swift requires Xcode's command-line tools which live outside the Nix store
    __noChroot = true;

    # stdenv fixup uses GNU find/cut flags unavailable on macOS BSD tools
    dontFixup = true;

    buildPhase = ''
      XCODE="/Applications/Xcode.app/Contents/Developer"
      SWIFTC="$XCODE/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
      SDK="$XCODE/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
      export DEVELOPER_DIR="$XCODE"
      export SDKROOT="$SDK"
      export PATH="$XCODE/Toolchains/XcodeDefault.xctoolchain/usr/bin:$XCODE/usr/bin:/usr/bin:$PATH"
      "$SWIFTC" -O -sdk "$SDK" -o mapq main.swift
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp mapq $out/bin/
    '';
  };

}
