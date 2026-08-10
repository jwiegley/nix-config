{
  pkgs,
  package,
}:

let
  nodePackage = package.override { useBun = false; };
  piSourceBuild = pkgs.callPackage ../../../packages/pi-source-build.nix { };
in
assert nodePackage ? overrideAttrs;
assert nodePackage.version == piSourceBuild.version;
nodePackage.overrideAttrs (old: {
  preInstall = ''
    rm -rf dist
    cp -R ${piSourceBuild}/coding-agent/dist ./dist
    chmod -R u+w dist
    rm -rf node_modules/@earendil-works/pi-agent-core/dist
    cp -R ${piSourceBuild}/agent/dist node_modules/@earendil-works/pi-agent-core/dist
    chmod -R u+w node_modules/@earendil-works/pi-agent-core/dist
    patch -p1 --fuzz=0 < ${../../../overlays/ai/patches/pi-system-prompt-no-docs.patch}
    substituteInPlace dist/core/system-prompt.js \
      --replace-fail '//# sourceMappingURL=system-prompt.js.map' ""
    rm -f dist/core/system-prompt.js.map
    patch -p1 --fuzz=0 < ${../../../overlays/ai/patches/pi-tool-renderer-wrapper.patch}
    # Keep the model picker responsive when pi.dev's optional remote
    # catalogs are unavailable. The picker still refreshes on demand,
    # but it starts from the cached catalog and owns its short timeout.
    patch -p1 --fuzz=0 < ${../../../overlays/ai/patches/pi-model-catalog-refresh.patch}
    for openai_api in \
      node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js \
      node_modules/@earendil-works/pi-ai/dist/api/openai-responses.js
    do
      substituteInPlace "$openai_api" \
        --replace-fail \
          '        defaultHeaders: headers,' \
          $'        defaultHeaders: headers,\n        timeout:\n            model.provider === "omlx" || model.provider === "llama-swap"\n                ? 7_200_000\n                : undefined,'
    done
    substituteInPlace dist/core/http-dispatcher.js \
      --replace-fail \
        'DEFAULT_HTTP_IDLE_TIMEOUT_MS = 300_000' \
        'DEFAULT_HTTP_IDLE_TIMEOUT_MS = 7_200_000'
    for patched_js in \
      dist/core/agent-session.js \
      dist/core/extensions/loader.js \
      dist/core/extensions/runner.js \
      dist/core/http-dispatcher.js \
      dist/modes/interactive/components/model-selector.js \
      dist/modes/interactive/interactive-mode.js \
      node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js \
      node_modules/@earendil-works/pi-ai/dist/api/openai-responses.js
    do
      map_file="$patched_js.map"
      map_name="''${map_file##*/}"
      substituteInPlace "$patched_js" \
        --replace-fail "//# sourceMappingURL=$map_name" ""
      rm -f "$map_file"
    done
    rm -f dist/core/extensions/tool-renderers.js.map
    ${pkgs.nodejs_24}/bin/node \
      ${../../../test/ai/pi-tool-renderer-wrapper.test.mjs} "$PWD"
    ${pkgs.nodejs_24}/bin/node \
      ${../../../test/ai/pi-model-catalog-refresh.test.mjs} "$PWD"
  ''
  + (old.preInstall or "");

  postInstall = (old.postInstall or "") + ''
    wrapProgram "$out/bin/pi" \
      --set PI_PACKAGE_DIR "$out/lib/node_modules/@earendil-works/pi-coding-agent"
  '';

  passthru = (old.passthru or { }) // {
    toolRendererWrapperAbi = 1;
  };
})
