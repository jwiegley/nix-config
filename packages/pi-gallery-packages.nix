{
  buildNpmPackage,
  buildPackages,
  chromium,
  fetchurl,
  findutils,
  inputs,
  jq,
  lib,
  makeWrapper,
  patchelf,
  playwright-driver,
  python3,
  runCommand,
  stdenv,
  writeShellScript,
}:

let
  packageRoot = package: name: "${package}/share/pi-packages/${name}";

  releaseTarballs = {
    pi-hashline-edit-pro = fetchurl {
      url = "https://registry.npmjs.org/pi-hashline-edit-pro/-/pi-hashline-edit-pro-0.17.5.tgz";
      hash = "sha256-WrPRKhBNUJc6l4u1v4k8dftGUQA2Pj754zE07h3QTxU=";
    };
    pi-web-access = fetchurl {
      url = "https://registry.npmjs.org/pi-web-access/-/pi-web-access-0.13.0.tgz";
      hash = "sha256-GmPsueJdqj4Ny+fxlwMWRVnehe4bv1GeiBo0i5uAQAA=";
    };
    pi-lens = fetchurl {
      url = "https://registry.npmjs.org/pi-lens/-/pi-lens-3.8.71.tgz";
      hash = "sha256-YoBaBtZx5dz3QOtGharxOyVG/qlcmOTbAFVrlJ4fhqw=";
    };
    pi-dynamic-workflows = fetchurl {
      url = "https://registry.npmjs.org/@quintinshaw/pi-dynamic-workflows/-/pi-dynamic-workflows-3.4.1.tgz";
      hash = "sha256-5bCDyn+yzRr3rUxDzHT+bGbGxYrv8gSl7S3YhN+pZ0U=";
    };
    pi-agent-browser-native = fetchurl {
      url = "https://registry.npmjs.org/pi-agent-browser-native/-/pi-agent-browser-native-0.2.72.tgz";
      hash = "sha256-3subgZHSxRN4wigNrM0KO6o2QmNSr8PtdrT4mg2kRlE=";
    };
    pi-lean-ctx = fetchurl {
      url = "https://registry.npmjs.org/pi-lean-ctx/-/pi-lean-ctx-3.9.12.tgz";
      hash = "sha256-/DMfx45WnZU4/aFMBpg69T0WcNOtwxGcq/8habW6hpg=";
    };
    agent-browser = fetchurl {
      url = "https://registry.npmjs.org/agent-browser/-/agent-browser-0.33.0.tgz";
      hash = "sha256-Zdcyp6DFLuT1kCXvBX7ztk2GqqdiYrpk9IrBF4iJz4M=";
    };
  };

  deniedNpx = writeShellScript "pi-lens-npx-disabled" ''
    echo "pi-lens: runtime package downloads are disabled; provide the tool through Nix or PATH" >&2
    exit 127
  '';

  mkReleaseSource =
    {
      name,
      tarball,
      lockFile,
      dropPeerMetadata ? true,
      hashline ? false,
      lens ? false,
      webAccess ? false,
      dynamicWorkflows ? false,
    }:
    runCommand "${name}-release-source"
      {
        nativeBuildInputs = [
          jq
          python3
        ];
      }
      ''
        mkdir -p "$out"
        tar -xzf ${tarball} -C "$out" --strip-components=1

        ${jq}/bin/jq '
          del(.devDependencies)
          ${lib.optionalString dropPeerMetadata "| del(.peerDependencies, .peerDependenciesMeta)"}
          ${lib.optionalString hashline ''
            | del(.dependencies["better-sqlite3"], .allowScripts)
          ''}
          ${lib.optionalString lens ''
            | del(.dependencies["@earendil-works/pi-tui"], .dependencies.typebox)
          ''}
        ' "$out/package.json" > "$out/package.json.normalized"
        mv "$out/package.json.normalized" "$out/package.json"
        cp ${lockFile} "$out/package-lock.json"

        ${lib.optionalString hashline ''
          substituteInPlace "$out/src/hash-store.ts" \
            --replace-fail \
              'async function tryLoadBetter(): Promise<boolean> {' \
              $'async function tryLoadBetter(): Promise<boolean> {\n  // Bun standalone aborts before the native import can fall back.\n  return false;'
        ''}

        ${lib.optionalString webAccess ''
          substituteInPlace "$out/index.ts" \
            --replace-fail 'loadConfig().provider' \
              '(process.env.PI_WEB_ACCESS_PROVIDER ?? loadConfig().provider)'
        ''}

        ${lib.optionalString dynamicWorkflows ''
          substituteInPlace "$out/extensions/workflow.ts" \
            --replace-fail \
              'excludeSubagentTools: settings.excludeSubagentTools,' \
              'excludeSubagentTools: ["subagent", ...(settings.excludeSubagentTools ?? [])],'
        ''}

        ${lib.optionalString lens ''
            ${python3}/bin/python3 - "$out" ${lib.escapeShellArg deniedNpx} <<'PY'
          from pathlib import Path
          import sys

          root = Path(sys.argv[1])
          denied_npx = sys.argv[2]

          installer = root / "dist/clients/installer/index.js"
          text = installer.read_text()
          start = text.index("export async function installTool(toolId) {")
          end = text.index("/**\n * Ensure a tool is installed", start)
          replacement = """export async function installTool(toolId) {
              logSessionStart(`auto-install ''${toolId}: disabled by Nix policy`);
              return false;
          }
          """
          installer.write_text(text[:start] + replacement + text[end:])

          interactive = root / "dist/clients/lsp/interactive-install.js"
          text = interactive.read_text()
          start = text.index("async function installTool(config) {")
          end = text.index("/**\n * Prompt user for installation", start)
          replacement = """async function installTool(_config) {
              return false;
          }
          """
          interactive.write_text(text[:start] + replacement + text[end:])

          policy = root / "dist/clients/tool-policy.js"
          text = policy.read_text()
          count = text.count("autoInstall: true")
          if count != 20:
              raise SystemExit(f"unexpected pi-lens auto-install policy count: {count}")
          policy.write_text(text.replace("autoInstall: true", "autoInstall: false"))

          replaced = 0
          for path in (root / "dist").rglob("*.js"):
              text = path.read_text()
              new = text.replace('"npx.cmd"', repr(denied_npx)).replace('"npx"', repr(denied_npx))
              if new != text:
                  replaced += 1
                  path.write_text(new)
          if replaced != 9:
              raise SystemExit(f"unexpected pi-lens npx file count: {replaced}")
          PY
        ''}
      '';

  mkNpmPackageRoot =
    {
      pname,
      version,
      src,
      npmDepsHash,
    }:
    buildNpmPackage {
      inherit
        pname
        version
        src
        npmDepsHash
        ;
      nodejs = buildPackages.nodejs_22;
      npmInstallFlags = [
        "--ignore-scripts"
        "--omit=dev"
        "--omit=peer"
        "--legacy-peer-deps"
      ];
      dontNpmBuild = true;
      makeCacheWritable = true;
      installPhase = ''
        runHook preInstall
        root="$out/share/pi-packages/${pname}"
        mkdir -p "$root"
        cp -R -- . "$root"/
        runHook postInstall
      '';
    };

  hashlineSource = mkReleaseSource {
    name = "pi-hashline-edit-pro";
    tarball = releaseTarballs.pi-hashline-edit-pro;
    lockFile = ./pi-gallery-locks/pi-hashline-edit-pro-package-lock.json;
    hashline = true;
  };
  webAccessSource = mkReleaseSource {
    name = "pi-web-access";
    tarball = releaseTarballs.pi-web-access;
    lockFile = ./pi-gallery-locks/pi-web-access-package-lock.json;
    dropPeerMetadata = false;
    webAccess = true;
  };
  lensSource = mkReleaseSource {
    name = "pi-lens";
    tarball = releaseTarballs.pi-lens;
    lockFile = ./pi-gallery-locks/pi-lens-package-lock.json;
    lens = true;
  };
  dynamicWorkflowsSource = mkReleaseSource {
    name = "pi-dynamic-workflows";
    tarball = releaseTarballs.pi-dynamic-workflows;
    lockFile = ./pi-gallery-locks/pi-dynamic-workflows-package-lock.json;
    dynamicWorkflows = true;
  };

  pi-hashline-edit-pro = mkNpmPackageRoot {
    pname = "pi-hashline-edit-pro";
    version = "0.17.5";
    src = hashlineSource;
    npmDepsHash = "sha256-sk7mvBP3/SwAFt3GYN1OL2SwNk1s5nC47UUsT1cxB2Y=";
  };
  pi-web-access = mkNpmPackageRoot {
    pname = "pi-web-access";
    version = "0.13.0";
    src = webAccessSource;
    npmDepsHash = "sha256-8onTvv7nUrTXMGvwkMkPEYc+mtpxolzF6Z9EuuB9pbs=";
  };
  pi-lens = mkNpmPackageRoot {
    pname = "pi-lens";
    version = "3.8.71";
    src = lensSource;
    npmDepsHash = "sha256-QZClnuBwVYZ+h5lb4YqsJ6VzgWyQQdnTMa05UdzcB78=";
  };
  pi-dynamic-workflows = mkNpmPackageRoot {
    pname = "pi-dynamic-workflows";
    version = "3.4.1";
    src = dynamicWorkflowsSource;
    npmDepsHash = "sha256-49v98jLmhF0K40OoVimaGy8DXpDrsWuhGsKuPbqsm1U=";
  };

  mkCopyRoot =
    {
      pname,
      version,
      install,
    }:
    runCommand "${pname}-${version}" { passthru = { inherit version; }; } ''
      root="$out/share/pi-packages/${pname}"
      mkdir -p "$root"
      ${install "$root"}
    '';

  bigpowers = mkCopyRoot {
    pname = "bigpowers";
    version = "2.82.3";
    install = root: ''
      cp -R -- ${inputs.bigpowers}/.pi ${root}/
      cp -- ${inputs.bigpowers}/package.json ${inputs.bigpowers}/LICENSE \
        ${inputs.bigpowers}/README.md ${root}/
    '';
  };

  pi-ponytail = mkCopyRoot {
    pname = "pi-ponytail";
    version = "4.8.4";
    install = root: ''
      cp -R -- ${inputs.ponytail}/pi-extension ${inputs.ponytail}/hooks \
        ${inputs.ponytail}/skills ${root}/
      cp -- ${inputs.ponytail}/package.json ${inputs.ponytail}/LICENSE \
        ${inputs.ponytail}/README.md ${root}/
    '';
  };

  pi-agent-browser-native = mkCopyRoot {
    pname = "pi-agent-browser-native";
    version = "0.2.72";
    install = root: ''
      tar -xzf ${releaseTarballs.pi-agent-browser-native} -C ${root} \
        --strip-components=1
    '';
  };

  pi-lean-ctx = mkCopyRoot {
    pname = "pi-lean-ctx";
    version = "3.9.12";
    install = root: ''
      tar -xzf ${releaseTarballs.pi-lean-ctx} -C ${root} \
        --strip-components=1
      cp -- ${inputs.lean-ctx}/LICENSE ${root}/LICENSE
    '';
  };

  lean-ctx = inputs.llm-agents.packages.${stdenv.hostPlatform.system}.lean-ctx;

  agent-browser =
    runCommand "agent-browser-0.33.0"
      {
        nativeBuildInputs = [
          findutils
          makeWrapper
        ]
        ++ lib.optional stdenv.hostPlatform.isLinux patchelf;
        passthru.version = "0.33.0";
        meta.mainProgram = "agent-browser";
      }
      ''
        package="$out/libexec/agent-browser"
        mkdir -p "$package" "$out/bin"
        tar -xzf ${releaseTarballs.agent-browser} -C "$package" --strip-components=1

        ${
          if stdenv.hostPlatform.isDarwin then
            ''
              binary="$package/bin/agent-browser-darwin-${
                if stdenv.hostPlatform.isAarch64 then "arm64" else "x64"
              }"
              browser_executable=$(${findutils}/bin/find -L ${playwright-driver.browsers} -type f \
                -path '*/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing' \
                -print -quit)
            ''
          else
            ''
              binary="$package/bin/agent-browser-linux-${
                if stdenv.hostPlatform.isAarch64 then "arm64" else "x64"
              }"
              browser_executable=${chromium}/bin/chromium
            ''
        }
        chmod 0755 "$binary"
        ${lib.optionalString stdenv.hostPlatform.isLinux ''
          patchelf --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
            --set-rpath ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]} "$binary"
        ''}
        test -x "$binary"
        test -x "$browser_executable"
        makeWrapper "$binary" "$out/bin/agent-browser" \
          --set-default AGENT_BROWSER_EXECUTABLE_PATH "$browser_executable"
      '';

  roots = {
    hashline = packageRoot pi-hashline-edit-pro "pi-hashline-edit-pro";
    web = packageRoot pi-web-access "pi-web-access";
    lens = packageRoot pi-lens "pi-lens";
    ponytail = packageRoot pi-ponytail "pi-ponytail";
    workflows = packageRoot pi-dynamic-workflows "pi-dynamic-workflows";
    browser = packageRoot pi-agent-browser-native "pi-agent-browser-native";
    lean = packageRoot pi-lean-ctx "pi-lean-ctx";
  };

  projection = {
    packages = [
      {
        name = "pi-hashline-edit-pro";
        version = "0.17.5";
        extensions = [ "${roots.hashline}/index.ts" ];
      }
      {
        name = "pi-web-access";
        version = "0.13.0";
        extensions = [ "${roots.web}/index.ts" ];
        skills = [ "${roots.web}/skills" ];
      }
      {
        name = "pi-lens";
        version = "3.8.71";
        extensions = [ "${roots.lens}/dist/index.js" ];
        skills = [ "${roots.lens}/skills" ];
      }
      {
        name = "@dietrichgebert/ponytail";
        version = "4.8.4+${builtins.substring 0 7 inputs.ponytail.rev}";
        extensions = [ "${roots.ponytail}/pi-extension/index.js" ];
        skills = [ ];
      }
      {
        name = "@quintinshaw/pi-dynamic-workflows";
        version = "3.4.1";
        extensions = [ "${roots.workflows}/extensions/workflow.ts" ];
        skills = [
          "${roots.workflows}/skills/workflow-authoring"
          "${roots.workflows}/skills/workflow-patterns"
        ];
      }
      {
        name = "pi-agent-browser-native";
        version = "0.2.72";
        extensions = [ "${roots.browser}/dist/extensions/agent-browser/index.js" ];
      }
      {
        name = "pi-lean-ctx";
        version = "3.9.12";
        extensions = [ "${roots.lean}/extensions/index.ts" ];
      }
    ];
  };

  pi-gallery =
    runCommand "pi-gallery"
      {
        passthru = {
          inherit projection roots;
          packages = {
            inherit
              agent-browser
              bigpowers
              lean-ctx
              pi-agent-browser-native
              pi-dynamic-workflows
              pi-hashline-edit-pro
              pi-lean-ctx
              pi-lens
              pi-ponytail
              pi-web-access
              ;
          };
        };
      }
      ''
        root="$out/share/pi-gallery"
        mkdir -p "$root"
        cat > "$root/index.ts" <<'TS'
        import hashline from ${builtins.toJSON "${roots.hashline}/index.ts"};
        import webAccess from ${builtins.toJSON "${roots.web}/index.ts"};
        import lens from ${builtins.toJSON "${roots.lens}/dist/index.js"};
        import ponytail from ${builtins.toJSON "${roots.ponytail}/pi-extension/index.js"};
        import workflows from ${builtins.toJSON "${roots.workflows}/extensions/workflow.ts"};
        import browser from ${builtins.toJSON "${roots.browser}/dist/extensions/agent-browser/index.js"};
        import leanCtx from ${builtins.toJSON "${roots.lean}/extensions/index.ts"};

        export default async function nixGallery(pi: unknown) {
          process.env.PI_WEB_ACCESS_PROVIDER = "perplexity";
          process.env.PI_LENS_DISABLE_LSP_INSTALL = "1";
          process.env.PI_LENS_AUTO_INSTALL = "0";
          process.env.LEAN_CTX_BIN = ${builtins.toJSON "${lean-ctx}/bin/lean-ctx"};

          for (const extension of [hashline, webAccess, lens, ponytail, workflows, browser, leanCtx]) {
            await extension(pi as never);
          }

          (pi as { on: (event: string, handler: () => unknown) => void }).on("resources_discover", () => ({
            skillPaths: ${builtins.toJSON (lib.concatMap (item: item.skills or [ ]) projection.packages)},
          }));
        }
        TS
        cat > "$root/projection.json" <<'JSON'
        ${builtins.toJSON projection}
        JSON
      '';
in
assert inputs.agent-browser-source.rev == "1ed371f3af472cc0d6cd8fdaea75d1a085ff7534";
assert inputs.agent-browser-source.narHash == "sha256-praWvAgWoDmWqXzh/kxdfQAPGkVS4qkb0pPYtMWO/N8=";
assert
  builtins.hashFile "sha256" "${inputs.agent-browser-source}/cli/Cargo.toml"
  == "6880ec45ed03e83ab22bd21ac63c4dbaf6c8accd4da840dcf7536e5e48b1f98d";
assert inputs.pi-hashline-edit-pro.rev == "5d97f2a0d8aaa0e06a637583845263ed2ca455f1";
assert inputs.pi-hashline-edit-pro.narHash == "sha256-UOAalDCmw/bnRWU76eIOP+sHBc43BmDXZF5D8J0v9G4=";
assert inputs.pi-web-access.rev == "7bdc30a65cf77273eb9c0034647b373bda4060d7";
assert inputs.pi-web-access.narHash == "sha256-TPtkurLY8Z9qxa597e0C5yWlNvgz4ywv2GdQstTB33A=";
assert inputs.pi-lens.rev == "2ea8691a25e3a39bf944e0d1c5ed4178c50b55da";
assert inputs.pi-lens.narHash == "sha256-lrBLV94SNHVFbt7leVjOY1dJV6HszjnOqTks8rFtfZk=";
assert inputs.pi-dynamic-workflows.rev == "6d866e16396ca487dfde2591dd4d4e7ab04e9ba1";
assert inputs.pi-dynamic-workflows.narHash == "sha256-lFb9rmmnywPwnZMBcfn5JusqASdaA1g7663s2znfS+o=";
assert inputs.pi-agent-browser-native.rev == "211a012c9b199d758768e8ba729f35e11e661f65";
assert
  inputs.pi-agent-browser-native.narHash == "sha256-LMVvFkxiDN90lcTX54FmrwM0N/lLV+IJaCWzveHqpm8=";
assert inputs.lean-ctx.rev == "54e0a66bcbb9a6695e45848d3ea97a491a0b5275";
assert inputs.lean-ctx.narHash == "sha256-h0blm9mUezoMVZ7OaJDhfioTBKUiMk70KejC2gihgBc=";
{
  inherit
    agent-browser
    bigpowers
    lean-ctx
    pi-agent-browser-native
    pi-dynamic-workflows
    pi-gallery
    pi-hashline-edit-pro
    pi-lean-ctx
    pi-lens
    pi-ponytail
    pi-web-access
    ;
}
