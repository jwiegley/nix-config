{
  emacs-nox,
  runCommand,
}:

runCommand "edit-env-tests" { nativeBuildInputs = [ emacs-nox ]; } ''
  emacs --batch -Q \
    -L ${../../overlays/emacs} \
    -l ${./edit-env-test.el} \
    -f ert-run-tests-batch-and-exit
  touch "$out"
''
