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
      version = "1.3.1";
      pyproject = true;

      src = fetchFromGitHub {
        owner = "Ruya-AI";
        repo = "cozempic";
        tag = "v${version}";
        hash = "sha256-IffcUePmIDHpN4o630IYmJmYiSOtpuZutr+FZfAyulI=";
      };

      build-system = [ setuptools ];

      # The guard daemon forks using `sys.executable -m cozempic.cli`
      # which bypasses the Nix wrapper's site.addsitedir() injection.
      # Setting PYTHONPATH ensures the forked process can find the module.
      makeWrapperArgs = [
        "--set"
        "PYTHONPATH"
        "${placeholder "out"}/${prev.python3.sitePackages}"
      ];

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
