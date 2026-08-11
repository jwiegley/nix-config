{
  bash,
  coreutils,
  findutils,
  runCommand,
}:

runCommand "samba-darwin-fixup-tests"
  {
    nativeBuildInputs = [
      bash
      coreutils
      findutils
    ];
  }
  ''
    FIXUP_SCRIPT=${../../overlays/samba-darwin-fixup.sh} \
      ${bash}/bin/bash ${./samba-darwin-fixup-test.sh}
    touch "$out"
  ''
