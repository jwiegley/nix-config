{
  pkgs,
  scriptsSource,
  modelPolicy ? import ../../config/ai/models.nix,
  hostPolicy ? import ../../config/hosts.nix,
}:

let
  python = pkgs.python3.withPackages (packages: [ packages.pytest ]);
  policyFile = pkgs.writeText "script-model-policy.json" (builtins.toJSON modelPolicy);
  hostPolicyFile = pkgs.writeText "script-host-policy.json" (
    builtins.toJSON {
      inherit (hostPolicy) hosts usernames scriptEndpoints;
    }
  );
in
pkgs.stdenvNoCC.mkDerivation {
  name = "script-model-policy-check";
  src = scriptsSource;
  nativeBuildInputs = [
    python
    pkgs.bash
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.git
    pkgs.getopt
    pkgs.jq
  ];
  dontConfigure = true;
  buildPhase = ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export LANG=C.UTF-8
    mkdir -p "$XDG_CONFIG_HOME"
    test -x model_policy.py
    python3 -m unittest -v test_model_policy > model-policy.log 2>&1 || {
      cat model-policy.log >&2
      exit 1
    }
    NIX_TEST_MODEL_POLICY=${policyFile} NIX_TEST_HOST_POLICY=${hostPolicyFile} \
      python3 -m unittest -v test_model_policy > nix-model-policy.log 2>&1 || {
        cat nix-model-policy.log >&2
        exit 1
      }
    python3 -m unittest -v test_gemini_to_org > transcript.log 2>&1 || {
      cat transcript.log >&2
      exit 1
    }
    python3 -m pytest -q test_dispatch_agent_note.py > dispatcher.log 2>&1 || {
      cat dispatcher.log >&2
      exit 1
    }
  '';
  installPhase = ''
    mkdir -p "$out"
    cp model-policy.log nix-model-policy.log transcript.log dispatcher.log "$out/"
  '';
}
