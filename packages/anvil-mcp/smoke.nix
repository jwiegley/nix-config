{
  anvilMcp,
  python3,
  runCommand,
}:

runCommand "anvil-mcp-smoke"
  {
    nativeBuildInputs = [
      anvilMcp
      python3
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    ${python3}/bin/python ${./smoke.py} ${anvilMcp}/bin/anvil-mcp
    touch "$out"
  ''
