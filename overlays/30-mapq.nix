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

    buildPhase = ''
      # Bypass xcrun entirely — use the Xcode swiftc and SDK directly
      XCODE_DEV="/Applications/Xcode.app/Contents/Developer"
      SWIFTC="$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
      SDKROOT="$XCODE_DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
      export DEVELOPER_DIR="$XCODE_DEV"
      export SDKROOT
      "$SWIFTC" -O -sdk "$SDKROOT" -o mapq main.swift 2>&1
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp mapq $out/bin/
    '';
  };

}
