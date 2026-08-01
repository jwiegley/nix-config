# overlays/30-claude-vault.nix
# Purpose: claude-vault - Archive Claude Code conversations into searchable SQLite
# Dependencies: Uses prev only
# Packages: claude-vault
_final: prev:
let
  source = (import ../../packages/source-catalog.nix "ai").claude-vault;
in
{

  claude-vault =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "claude-vault";
      inherit (source) version;

      src =
        assert source.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub source.source.args;

      cargoHash = source.hashes.cargoHash;

      # Upstream's release tag is newer than the crate version in Cargo.toml
      # (both Cargo.toml and Cargo.lock still declare 0.1.0), so clap's
      # `#[command(version)]` reported `claude-vault 0.1.0`.  Rewrite the
      # crate's own version in both files so `--version` matches the pinned
      # release.  Done in preBuild — after the cargo vendor/setup hook has
      # run during patchPhase — so the edit can neither be clobbered by, nor
      # trip, the lockfile-consistency check.  Only this crate's version
      # line changes; the dependency graph is untouched, so cargoHash stays
      # valid.  Note: "version = \"0.1.0\"" is unique in Cargo.toml but not in
      # Cargo.lock, hence the name/version pair substitution for the lockfile.
      preBuild = ''
        substituteInPlace Cargo.toml \
          --replace-fail 'version = "0.1.0"' 'version = "${version}"'
        substituteInPlace Cargo.lock \
          --replace-fail \
          $'name = "claude-vault"\nversion = "0.1.0"' \
          $'name = "claude-vault"\nversion = "${version}"'
      '';

      meta = {
        description = "Archive Claude Code conversations into a searchable SQLite database";
        homepage = "https://github.com/kuroko1t/claude-vault";
        license = lib.licenses.mit;
        mainProgram = "claude-vault";
      };
    };

}
