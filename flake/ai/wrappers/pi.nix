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
  dontNpmPrune = true;
  preInstall = ''
    rm -rf dist
    cp -R ${piSourceBuild}/coding-agent/dist ./dist
    chmod -R u+w dist
    ${pkgs.nodejs_24}/bin/node -e \
      'const p = JSON.parse(require("node:fs").readFileSync("package.json", "utf8")); if (p.bin.pi !== "dist/bundle/cli.js") process.exit(1)'
    rm -rf node_modules/@earendil-works/pi-agent-core/dist
    cp -R ${piSourceBuild}/agent/dist node_modules/@earendil-works/pi-agent-core/dist
    chmod -R u+w node_modules/@earendil-works/pi-agent-core/dist
    cp "${piSourceBuild}/workspace/packages/agent/package.json" node_modules/@earendil-works/pi-agent-core/
    rm -rf node_modules/@earendil-works/pi-ai/dist
    cp -R ${piSourceBuild}/ai/dist node_modules/@earendil-works/pi-ai/dist
    chmod -R u+w node_modules/@earendil-works/pi-ai/dist
    cp "${piSourceBuild}/workspace/packages/ai/package.json" node_modules/@earendil-works/pi-ai/
    rm -rf node_modules/@earendil-works/pi-tui/dist
    cp -R "${piSourceBuild}/workspace/packages/tui/dist" node_modules/@earendil-works/pi-tui/
    cp "${piSourceBuild}/workspace/packages/tui/package.json" node_modules/@earendil-works/pi-tui/
    mkdir -p node_modules/@earendil-works/chord
    cp "${piSourceBuild}/workspace/packages/chord/package.json" node_modules/@earendil-works/chord/
    cp -R "${piSourceBuild}/workspace/packages/chord/dist" node_modules/@earendil-works/chord/
    mkdir -p node_modules/@earendil-works/pi-server
    cp "${piSourceBuild}/workspace/packages/server/package.json" node_modules/@earendil-works/pi-server/
    cp -R "${piSourceBuild}/workspace/packages/server/dist" node_modules/@earendil-works/pi-server/
    cp -R "${piSourceBuild}/workspace/node_modules/esbuild" node_modules/
    cp -R "${piSourceBuild}/workspace/node_modules/@esbuild" node_modules/
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
    ${pkgs.nodejs_24}/bin/node -e 'const fs = require("node:fs"); const [path, version] = process.argv.slice(1); const metadata = JSON.parse(fs.readFileSync(path, "utf8")); metadata.version = version; fs.writeFileSync(path, JSON.stringify(metadata, null, 2) + "\n");' "$out/lib/node_modules/@earendil-works/pi-coding-agent/package.json" "${piSourceBuild.version}"
    wrapProgram "$out/bin/pi" \
      --set PI_PACKAGE_DIR "$out/lib/node_modules/@earendil-works/pi-coding-agent"
  '';

  passthru = (old.passthru or { }) // {
    bundledCliAbi = 1;
    toolRendererWrapperAbi = 1;
  };
})
