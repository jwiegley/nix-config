{ runCommand, python, yq, }:
let venv = python.withPackages (ps: [ ps.llm ps.llm-mlx ]);
in runCommand "llm-mlx-test-llm-plugin" { nativeBuildInputs = [ venv yq ]; } ''
  llm plugins | yq --exit-status 'any(.name == "llm-mlx")'
  touch "$out"
''
