{
  lib,
  makeWrapper,
  org-jw,
  python3,
  stdenvNoCC,
}:

let
  runtimePython = python3.withPackages (pythonPackages: [
    pythonPackages.mcp
    pythonPackages.psycopg2
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "hermes-org-db-mcp";
  version = "1.0.0";
  src = ./org-db-mcp.py;

  strictDeps = true;
  dontUnpack = true;
  dontBuild = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    install -Dm0755 "$src" "$out/bin/org-db-mcp"
    substituteInPlace "$out/bin/org-db-mcp" \
      --replace-fail '#!/usr/bin/env python3' '#!${runtimePython}/bin/python3'
    wrapProgram "$out/bin/org-db-mcp" \
      --prefix PATH : ${lib.makeBinPath [ org-jw ]}
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    PYTHONDONTWRITEBYTECODE=1 \
      ${runtimePython}/bin/python3 \
      ${../../test/ai/hermes-org-db-mcp-contract.py} \
      "$src" "$out/bin/org-db-mcp" "${org-jw}/bin/org"
    runHook postInstallCheck
  '';

  meta = {
    description = "Read-only Org PostgreSQL MCP server for Hermes Agent";
    mainProgram = "org-db-mcp";
    platforms = lib.platforms.unix;
  };
}
