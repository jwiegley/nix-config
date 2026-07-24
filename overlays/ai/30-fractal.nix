# overlays/30-fractal.nix
# Purpose: Plasma Fractal agent orchestration and its Wiki companion
# Dependencies: Python package set plus standard Unix runtime tools
# Packages: plasma-fractal, plasma-wiki
final: prev:

let
  inherit (prev) lib;
  ps = final.python3Packages;

  wikiRuntime = [
    prev.bash
    prev.coreutils
    prev.gawk
    prev.git
    prev.gnugrep
  ];

  plasmaWiki = ps.buildPythonApplication rec {
    pname = "plasma-wiki";
    version = "1.1.0";
    format = "wheel";

    src = ps.fetchPypi {
      pname = "plasma_wiki";
      inherit version;
      format = "wheel";
      dist = "py3";
      python = "py3";
      hash = "sha256-kZ5f3RrBoxK6GXs5xm+Ug7LcyS91XCY0CHkdkKssZys=";
    };

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

  fractalRuntime = [
    plasmaWiki
    prev.bash
    prev.coreutils
    prev.gawk
    prev.git
    prev.gnugrep
    prev.gnused
    prev.procps
    prev.tmux
  ];
in
{
  plasma-wiki = plasmaWiki;

  plasma-fractal = ps.buildPythonApplication rec {
    pname = "plasma-fractal";
    version = "1.0.0";
    format = "wheel";

    src = ps.fetchPypi {
      pname = "plasma_fractal";
      inherit version;
      format = "wheel";
      dist = "py3";
      python = "py3";
      hash = "sha256-ROekeFUmslh7y2h/cOMv7d2CCAc8PGxiJ7zNvr7pDoA=";
    };

    dependencies = [
      plasmaWiki
      ps.rich
      ps.textual
      ps.typer
    ];
    nativeBuildInputs = [
      prev.makeWrapper
      prev.patch
    ];
    makeWrapperArgs = [
      "--prefix PATH : ${lib.makeBinPath fractalRuntime}"
    ];

    postInstall = ''
      ${prev.patch}/bin/patch \
        --batch \
        --directory="$out/${ps.python.sitePackages}" \
        --forward \
        --fuzz=0 \
        --strip=1 \
        < ${./patches/plasma-fractal-nix-compat.patch}
      ${prev.patch}/bin/patch \
        --batch \
        --directory="$out/${ps.python.sitePackages}" \
        --forward \
        --fuzz=0 \
        --strip=1 \
        < ${./patches/plasma-fractal-native-pi.patch}
      mkdir -p "$out/share/skills"
      ln -s "$out/${ps.python.sitePackages}/fractal/skills/fractal" \
        "$out/share/skills/fractal"
    '';

    postFixup = ''
      wrapProgram "$out/bin/fractal" --prefix PATH : "$out/bin"
    '';

    doCheck = false;
    pythonImportsCheck = [
      "fractal"
      "fractal.tui"
      "fractal.impl.pi"
    ];
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      test "$("$out/bin/fractal" --version)" = "${version}"
      test -f "$out/share/skills/fractal/SKILL.md"
      test -f "$out/share/skills/fractal/agents/openai.yaml"
      "$out/bin/fractal" --help > /dev/null
      "$out/bin/fractal" node init --help | grep -F "pi" > /dev/null
      runHook postInstallCheck
    '';

    meta = {
      description = "Hierarchical agent loops with recursive self-organization";
      homepage = "https://github.com/plasma-ai/fractal";
      license = lib.licenses.asl20;
      mainProgram = "fractal";
      platforms = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    };
  };
}
