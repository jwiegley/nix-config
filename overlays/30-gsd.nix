# overlays/30-gsd.nix
# Purpose: get-shit-done (gsd) - meta-prompting and spec-driven development for Claude Code
# Dependencies: None (uses only prev)
# Packages: get-shit-done-cc
final: prev: {

  get-shit-done-cc =
    with prev;
    buildNpmPackage (finalAttrs: {
      pname = "get-shit-done-cc";
      version = "1.20.5";

      src = fetchFromGitHub {
        owner = "gsd-build";
        repo = "get-shit-done";
        tag = "v${finalAttrs.version}";
        hash = "sha256-m0kRPIP5XnoeAnIEj6TZ85C8pw36Y/zLEbnX9dyjAd4=";
      };

      npmDepsHash = "sha256-8iTfmUhQilQSZSzVZ0DRSYBPpqu6gM3CI7MkawxTBkY=";

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
