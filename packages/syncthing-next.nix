{
  fetchFromGitHub,
  syncthing,
}:

let
  source = (import ./source-catalog.nix "compatibility").syncthing-next;
in
syncthing.overrideAttrs (
  _finalAttrs: _previousAttrs: {
    inherit (source) version;
    src =
      assert source.source.fetcher == "fetchFromGitHub";
      fetchFromGitHub source.source.args;
    vendorHash = source.hashes.vendorHash;
  }
)
