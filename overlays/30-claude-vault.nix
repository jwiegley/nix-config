# overlays/30-claude-vault.nix
# Purpose: claude-vault - Archive Claude Code conversations into searchable SQLite
# Dependencies: Uses prev only
# Packages: claude-vault
final: prev: {

  claude-vault =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "claude-vault";
      version = "0.1.1";

      src = fetchFromGitHub {
        owner = "kuroko1t";
        repo = "claude-vault";
        tag = "v${version}";
        hash = "sha256-kOBEQeLVetT3xzd/XXnR+m5ra/CK+mOtRJ1n/rrAFtY=";
      };

      cargoHash = "sha256-BX35eHAvC8GUCaByJVCkNz6xAVHBOxAPeeuDNmHAphc=";

      meta = {
        description = "Archive Claude Code conversations into a searchable SQLite database";
        homepage = "https://github.com/kuroko1t/claude-vault";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
        mainProgram = "claude-vault";
      };
    };

}
