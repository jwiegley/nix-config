final: prev:

let
  inherit (prev) lib;
  ps = final.python3Packages;
  sources = import ../../packages/source-catalog.nix "ai";

  wikiRuntime = [
    prev.bash
    prev.coreutils
    prev.gawk
    prev.git
    prev.gnugrep
  ];

  plasmaWiki = ps.buildPythonApplication rec {
    pname = "plasma-wiki";
    inherit (sources.plasma-wiki) version;
    format = "wheel";

    src =
      assert sources.plasma-wiki.source.fetcher == "fetchPypi";
      ps.fetchPypi sources.plasma-wiki.source.args;

    dependencies = [ ps.typer ];
    nativeBuildInputs = [
      prev.makeWrapper
      prev.patch
    ];
    makeWrapperArgs = [
      "--prefix PATH : ${lib.makeBinPath wikiRuntime}"
    ];

    postInstall = ''
      ${prev.patch}/bin/patch \
        --batch \
        --directory="$out/${ps.python.sitePackages}" \
        --forward \
        --fuzz=0 \
        --strip=1 \
        < ${./patches/plasma-wiki-writable-obsidian.patch}
      mkdir -p "$out/share/skills"
      ln -s "$out/${ps.python.sitePackages}/wiki/skills/wiki" \
        "$out/share/skills/wiki"
    '';

    doCheck = false;
    pythonImportsCheck = [ "wiki" ];
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      test -f "$out/share/skills/wiki/SKILL.md"
      test -f "$out/share/skills/wiki/agents/openai.yaml"
      "$out/bin/wiki" --help > /dev/null
      runHook postInstallCheck
    '';

    meta = {
      description = "Local-first Markdown wiki and knowledge graph CLI";
      homepage = "https://github.com/plasma-ai/wiki";
      license = lib.licenses.asl20;
      mainProgram = "wiki";
      platforms = lib.platforms.unix;
    };
  };
in
{
  plasma-wiki = plasmaWiki;
}
