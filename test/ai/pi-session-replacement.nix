{
  nodejs_24,
  python3,
  runCommand,
  piPackage,
  src,
}:

runCommand "pi-session-replacement"
  {
    nativeBuildInputs = [
      nodejs_24
      python3
    ];
  }
  ''
    export HOME=$TMPDIR/home
    mkdir -p "$HOME"
    python3 ${src}/test/ai/pi-session-replacement-pty.py \
      ${piPackage}/bin/pi \
      ${piPackage}/lib/node_modules/@earendil-works/pi-coding-agent
    touch "$out"
  ''
