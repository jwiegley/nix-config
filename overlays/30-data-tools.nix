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
