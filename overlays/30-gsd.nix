# overlays/30-gsd.nix
# Purpose: get-shit-done (gsd) - meta-prompting and spec-driven development for Claude Code
# Dependencies: None (uses only prev)
# Packages: get-shit-done-cc
final: prev: {

  get-shit-done-cc =
    with prev;
    buildNpmPackage (finalAttrs: {
      pname = "get-shit-done-cc";
      version = "1.22.4";

      src = fetchFromGitHub {
        owner = "gsd-build";
        repo = "get-shit-done";
        tag = "v${finalAttrs.version}";
        hash = "sha256-Jx58gEpJWUrSktFuV9r8/3wIDTYYJUEp7r4k28v48OY=";
      };

      npmDepsHash = "sha256-dbvFfnCg9CHLeAsvQNbDeXmjvOVOQYc0tBXutn3jTIs=";

      # The prepublishOnly script builds hooks with esbuild; skip in nix build
      dontNpmBuild = true;

      makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

      meta = with lib; {
        description = "A meta-prompting, context engineering and spec-driven development system for Claude Code";
        homepage = "https://github.com/gsd-build/get-shit-done";
        license = licenses.mit;
        mainProgram = "get-shit-done-cc";
        maintainers = [ maintainers.jwiegley ];
        platforms = platforms.all;
      };
    });

}
