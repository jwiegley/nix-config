# overlays/30-claude-vault.nix
# Purpose: claude-vault - Archive Claude Code conversations into searchable SQLite
# Dependencies: Uses prev only
# Packages: claude-vault
final: prev: {

  claude-vault =
    with prev;
    rustPlatform.buildRustPackage rec {
      pname = "claude-vault";
      version = "0.1.2";

      src = fetchFromGitHub {
        owner = "kuroko1t";
        repo = "claude-vault";
        tag = "v${version}";
        hash = "sha256-YkumepLBY/kt78yYtl0RQilwW61uSC6v6E7aqnz6+i8=";
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
