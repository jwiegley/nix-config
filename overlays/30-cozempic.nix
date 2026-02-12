# overlays/30-cozempic.nix
# Purpose: Cozempic - Context cleaning for Claude Code sessions
# Dependencies: Uses prev only
# Packages: cozempic
final: prev: {

  cozempic =
    with prev;
    with prev.python3Packages;
    buildPythonApplication rec {
      pname = "cozempic";
      version = "0.5.0";
      pyproject = true;

      src = fetchFromGitHub {
        owner = "Ruya-AI";
        repo = "cozempic";
        tag = "v${version}";
        hash = "sha256-DLe7l+ALUSQ1xAdIJgAIDh7D5nDW6WcivybVyXGfjF4=";
      };

      build-system = [ setuptools ];

      doCheck = false;

      meta = {
        description = "Context cleaning for Claude Code — prune bloated sessions, protect Agent Teams from context loss";
        homepage = "https://github.com/Ruya-AI/cozempic";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
        mainProgram = "cozempic";
      };
    };

}
