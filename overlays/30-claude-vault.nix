# overlays/30-claude-vault.nix
# Purpose: claude-vault - Archive Claude Code conversations into searchable SQLite
# Dependencies: Uses prev only
# Packages: claude-vault
_final: prev: {

  claude-vault =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "claude-vault";
      version = "0.1.3";

      src = fetchFromGitHub {
        owner = "kuroko1t";
        repo = "claude-vault";
        tag = "v${version}";
        hash = "sha256-Och7ISW88DN4ZWTCDT84HD2E2tVOPWeTFjodrCDFzD4=";
      };

      cargoHash = "sha256-BX35eHAvC8GUCaByJVCkNz6xAVHBOxAPeeuDNmHAphc=";

      # Upstream tagged v0.1.3 but never bumped the crate version from 0.1.0
      # (both Cargo.toml and Cargo.lock still declare 0.1.0), so clap's
      # `#[command(version)]` reported `claude-vault 0.1.0`.  Rewrite the
      # crate's own version in both files so `--version` matches the pinned
      # release.  Done in preBuild — after the cargo vendor/setup hook has
      # run during patchPhase — so the edit can neither be clobbered by, nor
      # trip, the lockfile-consistency check.  Only this crate's version
      # line changes; the dependency graph is untouched, so cargoHash stays
      # valid.  Note: "version = \"0.1.0\"" is unique in Cargo.toml but not in
      # Cargo.lock, hence the name-anchored sed for the lockfile.
      preBuild = ''
        substituteInPlace Cargo.toml \
          --replace-fail 'version = "0.1.0"' 'version = "0.1.3"'
        sed -i '/^name = "claude-vault"$/{n;s/^version = "0.1.0"$/version = "0.1.3"/;}' Cargo.lock
      '';

      meta = {
        description = "Archive Claude Code conversations into a searchable SQLite database";
        homepage = "https://github.com/kuroko1t/claude-vault";
        license = lib.licenses.mit;
        mainProgram = "claude-vault";
      };
    };

}
