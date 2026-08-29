# Independent Model Context Protocol packages.
# Dependencies: Uses final for python3Packages; uses prev elsewhere
# Includes MCP servers and Claude Code tools.
{
  final,
  prev,
  llmAgents ? null,
  palMcpServer ? null,
}:

let
  sources = import ./source-catalog.nix "ai";
  droidPackage = llmAgents.packages.${prev.stdenv.hostPlatform.system}.droid;
  palPackage = builtins.fromTOML (builtins.readFile "${palMcpServer}/pyproject.toml");
  managedMcpPath = prev.lib.makeBinPath [
    prev.coreutils
    prev.openssh
  ];
in
prev.lib.optionalAttrs (palMcpServer != null && llmAgents != null) {

  # PAL MCP Server - Provider Abstraction Layer for multi-model AI collaboration
  # NOTE: Using 'final' because python3Packages may be modified by
  # pythonPackagesExtensions in other overlays
  pal-mcp-server =
    with final;
    with final.python3Packages;
    buildPythonApplication {
      pname = "pal-mcp-server";
      version = palPackage.project.version;
      pyproject = true;

      src = palMcpServer;

      # clink launches same-UID coding agents beneath the multi-provider PAL
      # process, so it cannot isolate provider keys or mutable client hooks.
      patches = [
        ../overlays/ai/patches/pal-mcp-server-disable-clink.patch
        ../overlays/ai/patches/pal-mcp-server-stderr-logging.patch
      ];

      build-system = [
        setuptools
        setuptools-scm
      ];

      dependencies = [
        mcp
        google-genai
        openai
        anthropic
        droid-sdk
        pydantic
        python-dotenv
      ];

      makeWrapperArgs = [
        "--set"
        "PAL_DROID_EXECUTABLE"
        (lib.getExe droidPackage)
      ];

      env.SETUPTOOLS_SCM_PRETEND_VERSION = palPackage.project.version;

      doCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck
        test -f "$out/${python.sitePackages}/conf/anthropic_models.json"
        test -f "$out/${python.sitePackages}/conf/factory_models.json"
        ${python.interpreter} ${../test/ai/overlays/pal-mcp-contract.py} \
          "$out" "$out/bin/pal-mcp-server" \
          ${lib.escapeShellArg palPackage.project.version}
        runHook postInstallCheck
      '';

      meta = {
        description = "AI-powered MCP server with multiple model providers";
        homepage = "https://github.com/jwiegley/pal-mcp-server";
        license = lib.licenses.asl20;
        mainProgram = "pal-mcp-server";
      };
    };

}
// {

  # Common environment boundary for catalog-managed stdio MCP servers.
  nix-managed-mcp-stdio =
    with prev;
    stdenv.mkDerivation {
      pname = "nix-managed-mcp-stdio";
      version = "1";
      src = ./nix-managed-mcp-stdio.c;
      dontUnpack = true;
      strictDeps = true;

      buildPhase = ''
        runHook preBuild
        $CC -std=c11 -Wall -Wextra -Werror -pedantic \
          -DNIX_MANAGED_MCP_PATH='"${managedMcpPath}"' \
          "$src" -o nix-managed-mcp-stdio
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        install -Dm0755 nix-managed-mcp-stdio "$out/bin/nix-managed-mcp-stdio"
        runHook postInstall
      '';

      meta = with lib; {
        description = "Environment boundary for managed stdio MCP servers";
        license = licenses.mit;
        mainProgram = "nix-managed-mcp-stdio";
        platforms = platforms.unix;
      };

      passthru.runtimePath = managedMcpPath;
    };

  # Rust documentation MCP server
  rustdocs-mcp-server =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "rustdocs-mcp-server";
      version = sources.rustdocs-mcp-server.version;

      src =
        assert sources.rustdocs-mcp-server.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.rustdocs-mcp-server.source.args;

      cargoHash = sources.rustdocs-mcp-server.hashes.cargoHash;

      nativeBuildInputs = [
        pkg-config
        perl
        openssl.dev
      ];

      meta = with lib; {
        description = ''
          Fetches the documentation for a specified Rust crate, generates
          embeddings for the content, and provides an MCP tool to answer questions
          about the crate based on the documentation context.
        '';
        homepage = "https://github.com/Govcraft/rust-docs-mcp-server";
        license = licenses.mit;
        mainProgram = "rustdocs_mcp_server";
      };
    };

  # Browser control MCP server
  browser-control-mcp =
    with prev;
    buildNpmPackage (_finalAttrs: {
      pname = "browser-control-mcp";
      version = sources.browser-control-mcp.version;

      src =
        assert sources.browser-control-mcp.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.browser-control-mcp.source.args;

      npmDepsHash = sources.browser-control-mcp.hashes.npmDepsHash;

      makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

      passthru.updateScript = nix-update-script { };

      doInstallCheck = true;
      versionCheckProgram = "${placeholder "out"}/bin/browser-control-mcp";
      versionCheckProgramArg = "--version";

      meta = with lib; {
        description = "MCP server paired with a browser extension that enables AI agents to control the user's browser.";
        homepage = "https://github.com/eyalzh/browser-control-mcp";
        license = licenses.mit;
        mainProgram = "browser-control-mcp";
        platforms = platforms.all;
      };
    });

  # claude-replay - Convert Claude Code transcripts to HTML replays
  claude-replay =
    with prev;
    buildNpmPackage (_finalAttrs: {
      pname = "claude-replay";
      version = sources.claude-replay.version;

      src =
        assert sources.claude-replay.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.claude-replay.source.args;

      npmDepsHash = sources.claude-replay.hashes.npmDepsHash;

      makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

      meta = with lib; {
        description = "Convert Claude Code session transcripts into interactive, shareable HTML replays";
        homepage = "https://github.com/es617/claude-replay";
        license = licenses.mit;
        mainProgram = "claude-replay";
        platforms = platforms.all;
      };
    });

  # Private web search through the configured SearXNG instance.
  mcp-searxng =
    let
      cleanLauncher = prev.writeShellScript "mcp-searxng-clean-launcher" ''
        set -euo pipefail
        searxng_url=''${SEARXNG_URL-}
        if (( $# == 1 )); then
          case $1 in
          -h | --help | -v | --version)
            searxng_url=''${searxng_url:-http://127.0.0.1}
            ;;
          esac
        fi
        : "''${searxng_url:?mcp-searxng requires SEARXNG_URL}"
        environment=(
          "HOME=''${TMPDIR:-/tmp}"
          "PATH=${prev.lib.makeBinPath [ prev.nodejs_22 ]}"
          "SEARXNG_URL=$searxng_url"
        )
        for name in LANG LC_ALL NIX_SSL_CERT_FILE NODE_EXTRA_CA_CERTS SSL_CERT_FILE TMPDIR; do
          if [[ -n ''${!name:-} ]]; then
            environment+=("$name=''${!name}")
          fi
        done
        exec ${prev.coreutils}/bin/env -i "''${environment[@]}" @server@ "$@"
      '';
    in
    with prev;
    buildNpmPackage (_finalAttrs: {
      pname = "mcp-searxng";
      version = sources.mcp-searxng.version;

      src =
        assert sources.mcp-searxng.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.mcp-searxng.source.args;

      npmDepsHash = sources.mcp-searxng.hashes.npmDepsHash;

      nodejs = nodejs_22;

      env.SEARXNG_URL = "http://127.0.0.1";

      postInstall = ''
        install -d "$out/libexec"
        mv "$out/bin/mcp-searxng" "$out/libexec/mcp-searxng"
        install -m0755 ${cleanLauncher} "$out/bin/mcp-searxng"
        substituteInPlace "$out/bin/mcp-searxng" \
          --replace-fail @server@ "$out/libexec/mcp-searxng"
      '';

      nativeInstallCheckInputs = [
        coreutils
        jq
      ];
      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck
        test "$("$out/bin/mcp-searxng" --version)" = ${lib.escapeShellArg sources.mcp-searxng.version}
        responses="$(
          cat <<'EOF' | timeout 10 "$out/bin/mcp-searxng"
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"nix-check","version":"1"}}}
        {"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
        {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
        EOF
        )"
        jq -e -s '
          any(.[]; .id == 1 and .result.protocolVersion == "2025-03-26")
          and any(.[]; .id == 2 and any(.result.tools[]?; .name == "searxng_web_search"))
        ' <<<"$responses" >/dev/null
        runHook postInstallCheck
      '';

      meta = with lib; {
        description = "Private web search for AI assistants through SearXNG";
        homepage = "https://github.com/ihor-sokoliuk/mcp-searxng";
        license = licenses.mit;
        mainProgram = "mcp-searxng";
        platforms = platforms.all;
      };
    });

  # drafts-mcp-server - MCP server that drives the Drafts app on macOS via
  # AppleScript (osascript). macOS-only by design (the upstream package.json
  # declares `"os": ["darwin"]`): it cannot run on Linux, so meta.platforms is
  # darwin and config/packages.nix installs it only under `isDarwin`. The
  # TypeScript source is compiled to dist/ by `tsc` (npm run build).
  drafts-mcp-server =
    with prev;
    buildNpmPackage (_finalAttrs: {
      pname = "drafts-mcp-server";
      version = sources.drafts-mcp-server.version;

      src =
        assert sources.drafts-mcp-server.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.drafts-mcp-server.source.args;

      npmDepsHash = sources.drafts-mcp-server.hashes.npmDepsHash;

      postPatch = ''
        substituteInPlace src/applescript.ts \
          --replace-fail "spawn('osascript'," "spawn('/usr/bin/osascript',"
      '';

      postInstall = ''
        compiled="$out/lib/node_modules/@agiletortoise/drafts-mcp-server/dist/applescript.js"
        test "$(grep -F -c "spawn('/usr/bin/osascript'," "$compiled")" -eq 2
        if grep -F "spawn('osascript'," "$compiled" >/dev/null; then
          echo "drafts-mcp-server retained a PATH-resolved osascript call" >&2
          exit 1
        fi
      '';

      makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

      meta = with lib; {
        description = "MCP server that lets AI assistants drive the Drafts app on macOS via AppleScript";
        homepage = "https://github.com/agiletortoise/drafts-mcp-server";
        license = licenses.mit;
        mainProgram = "drafts-mcp-server";
        platforms = platforms.darwin;
      };
    });

}
