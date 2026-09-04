{
  pkgs,
  package,
  piSource,
}:

let
  nodePackage = package.override { useBun = false; };
  piSourceBuild = pkgs.callPackage ../../../packages/pi-source-build.nix { inherit piSource; };
in
assert nodePackage ? overrideAttrs;
nodePackage.overrideAttrs (old: {
  __intentionallyOverridingVersion = true;
  inherit (piSourceBuild) version;
  preInstall = ''
    rm -rf dist
    cp -R ${piSourceBuild}/coding-agent/dist ./dist
    chmod -R u+w dist
    ${pkgs.nodejs_24}/bin/node -e \
      'const p = JSON.parse(require("node:fs").readFileSync("package.json", "utf8")); if (p.bin.pi !== "dist/bundle/cli.js") process.exit(1)'
    rm -rf node_modules/@earendil-works/pi-agent-core/dist
    cp -R ${piSourceBuild}/agent/dist node_modules/@earendil-works/pi-agent-core/dist
    chmod -R u+w node_modules/@earendil-works/pi-agent-core/dist
    rm -rf node_modules/@earendil-works/pi-ai/dist
    cp -R ${piSourceBuild}/ai/dist node_modules/@earendil-works/pi-ai/dist
    chmod -R u+w node_modules/@earendil-works/pi-ai/dist
    for spec in pi-client:client pi-protocol:protocol; do
      package="''${spec%%:*}"
      directory="''${spec#*:}"
      found=false
      for target in \
        "node_modules/@earendil-works/$package" \
        "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/$package"
      do
        if [ -d "$target" ]; then
          rm -rf "$target/dist"
          cp -R "${piSourceBuild}/workspace/packages/$directory/dist" "$target/dist"
          chmod -R u+w "$target/dist"
          found=true
        fi
      done
      "$found"
    done
    ${pkgs.nodejs_24}/bin/node \
      ${../../../test/ai/pi-tool-renderer-wrapper.test.mjs} "$PWD"
    ${pkgs.nodejs_24}/bin/node \
      ${../../../test/ai/pi-provider-transport.test.mjs} "$PWD"
    ${pkgs.nodejs_24}/bin/node \
      ${../../../test/ai/pi-model-catalog-refresh.test.mjs} "$PWD"
  ''
  + (old.preInstall or "");

  postInstall = (old.postInstall or "") + ''
    wrapProgram "$out/bin/pi" \
      --set PI_PACKAGE_DIR "$out/lib/node_modules/@earendil-works/pi-coding-agent"
  '';

  passthru = (old.passthru or { }) // {
    bundledCliAbi = 1;
    toolRendererWrapperAbi = 1;
  };
})
