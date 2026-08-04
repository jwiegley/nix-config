# Data processing and storage utilities.
{
  dirscan ? null,
}:
_final: prev:

let
  sources = import ../packages/source-catalog.nix "tools";
in
{
  hashdb =
    with prev;
    python3Packages.buildPythonApplication {
      pname = "hashdb";
      inherit (sources.hashdb) version;

      src =
        assert sources.hashdb.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.hashdb.source.args;

      pyproject = true;
      build-system = [ python3Packages.setuptools ];

      meta = {
        homepage = "https://github.com/jwiegley/hashdb";
        description = "File checksum database for duplicate detection";
        license = lib.licenses.bsd3;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

  unisessions =
    with prev;
    python3Packages.buildPythonApplication {
      pname = "unisessions";
      inherit (sources.unisessions) version;

      src =
        assert sources.unisessions.source.fetcher == "fetchPypi";
        python3Packages.fetchPypi sources.unisessions.source.args;

      pyproject = true;
      build-system = [ python3Packages.setuptools ];
      dependencies = with python3Packages; [
        fastmcp
        tiktoken
      ];

      postPatch = ''
        substituteInPlace pyproject.toml \
          --replace-fail \
          'unisessions-mcp = "unisessions.mcp_server:main"' \
          $'unisessions = "unisessions.cli:main"\nunisessions-mcp = "unisessions.mcp_server:main"'
      '';

      pythonImportsCheck = [
        "session_sdk"
        "unisessions"
      ];
      checkPhase = ''
        runHook preCheck
        python -m unittest discover -s tests
        runHook postCheck
      '';
      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck
        "$out/bin/unisessions" --help >/dev/null
        "$out/bin/unisessions-mcp" --help >/dev/null
        runHook postInstallCheck
      '';

      meta = {
        homepage = "https://github.com/vibheksoni/session-export";
        description = "Convert sessions between AI coding agents";
        license = lib.licenses.mit;
        mainProgram = "unisessions";
        platforms = lib.platforms.unix;
      };
    };

  tsvutils = prev.myLib.mkScriptPackage {
    name = "tsvutils-${sources.tsvutils.version}";
    src =
      assert sources.tsvutils.source.fetcher == "fetchFromGitHub";
      prev.fetchFromGitHub sources.tsvutils.source.args;
    description = "Utilities for processing tab-separated files";
    homepage = "https://github.com/brendano/tsvutils";
  };
}
// prev.lib.optionalAttrs (dirscan != null) {
  dirscan = dirscan.packages.${prev.stdenv.hostPlatform.system}.default;
}
