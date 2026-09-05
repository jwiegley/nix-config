{
  fetchFromGitHub,
  fetchgit,
  fetchurl,
  lib,
  python3,
  runCommand,
  swift,
  swiftPackages,
  swiftpm,
  unzip,
}:
let
  sources = import ./source-catalog.nix "tools";
  source = sources.vibeproxy;
  sparkleSource = sources."vibeproxy-sparkle";
  yamsSource = sources."vibeproxy-yams";

  appVersion = "1.8.287";
  buildNumber = "1112";
  cliProxyCommit = "7eb8b5c0c3f7224269ca49e3906984dc674b21c9";

  yams =
    assert yamsSource.source.fetcher == "fetchgit";
    fetchgit yamsSource.source.args;

  sparkleZip =
    assert sparkleSource.source.fetcher == "fetchurl";
    fetchurl sparkleSource.source.args;

  sparkle =
    runCommand "sparkle-swiftpm-${sparkleSource.version}" { nativeBuildInputs = [ unzip ]; }
      ''
        mkdir -p "$out"
        cd "$out"
        unzip -q ${sparkleZip}
      '';
in
swiftPackages.stdenv.mkDerivation {
  pname = "vibeproxy";
  version = "${appVersion}-droid-${source.version}";

  src =
    assert source.source.fetcher == "fetchFromGitHub";
    fetchFromGitHub source.source.args;

  strictDeps = true;
  nativeBuildInputs = [
    python3
    swift
    swiftpm
  ];

  postPatch = ''
    cat > src/Package.swift <<'EOF'
    // swift-tools-version: 5.9
    import PackageDescription

    let package = Package(
        name: "CLIProxyMenuBar",
        platforms: [
            .macOS(.v13)
        ],
        products: [
            .executable(
                name: "CLIProxyMenuBar",
                targets: ["CLIProxyMenuBar"]
            )
        ],
        dependencies: [
            .package(path: "Vendor/Yams")
        ],
        targets: [
            .binaryTarget(
                name: "Sparkle",
                path: "Vendor/Sparkle.xcframework"
            ),
            .executableTarget(
                name: "CLIProxyMenuBar",
                dependencies: ["Sparkle", "Yams"],
                path: "Sources",
                resources: [
                    .copy("Resources")
                ],
                linkerSettings: [
                    .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"])
                ]
            ),
            .testTarget(
                name: "CLIProxyMenuBarTests",
                dependencies: ["CLIProxyMenuBar"],
                path: "Tests"
            )
        ]
    )
    EOF
    rm -f src/Package.resolved
  '';

  configurePhase = ''
    runHook preConfigure
    mkdir -p src/Vendor/Yams
    cp -R ${yams}/. src/Vendor/Yams/
    chmod -R u+w src/Vendor
    cp -R ${sparkle}/Sparkle.xcframework src/Vendor/
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    pushd src
    TERM=dumb swift-build -c release
    popd
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    app="$out/Applications/VibeProxy.app"
    binPath="$(cd src && swift-build --show-bin-path -c release)"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
    install -m 0755 "$binPath/CLIProxyMenuBar" "$app/Contents/MacOS/CLIProxyMenuBar"
    cp -R src/Sources/Resources/. "$app/Contents/Resources/"
    install -m 0755 "$src/src/Sources/Resources/cli-proxy-api-plus" \
      "$app/Contents/Resources/cli-proxy-api-plus"
    cp -R "$binPath/Sparkle.framework" "$app/Contents/Frameworks/"
    cp src/Info.plist "$app/Contents/Info.plist"
    printf 'APPL????' > "$app/Contents/PkgInfo"
    python3 - "$app/Contents/Info.plist" <<PY
    import plistlib
    import sys

    path = sys.argv[1]
    with open(path, "rb") as stream:
        info = plistlib.load(stream)
    info["CFBundleShortVersionString"] = "${appVersion}"
    info["CFBundleVersion"] = "${buildNumber}"
    with open(path, "wb") as stream:
        plistlib.dump(info, stream, sort_keys=False)
    PY
    runHook postInstall

    # Critical runtime inputs come directly from the immutable source after hooks.
    install -m 0644 "$src/src/Sources/Resources/config.yaml" \
      "$app/Contents/Resources/config.yaml"
    cmp "$src/src/Sources/Resources/config.yaml" \
      "$app/Contents/Resources/config.yaml"
    cmp "$src/src/Sources/Resources/cli-proxy-api-plus" \
      "$app/Contents/Resources/cli-proxy-api-plus"
    grep -aF '${cliProxyCommit}' \
      "$app/Contents/Resources/cli-proxy-api-plus" >/dev/null
  '';

  # Preserve linker-generated ad-hoc signatures and the bundled frameworks.
  dontFixup = true;

  meta = {
    description = "Native macOS menu bar proxy with local Factory Droid support";
    homepage = source.source.url;
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
  };
}
