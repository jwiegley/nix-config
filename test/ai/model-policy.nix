{ lib, pkgs }:

let
  baseline = import ../../config/ai/models.nix;
  source = builtins.readFile ../../config/ai/models.nix;
  edits = [
    [
      (builtins.toJSON baseline.omlx.primary.name)
      (builtins.toJSON "model-policy-qwen-probe")
    ]
    [
      (builtins.toJSON baseline.omlx.reasoning.name)
      (builtins.toJSON "model-policy-reasoning-probe")
    ]
    [
      (builtins.toJSON baseline.embeddings.omlx)
      (builtins.toJSON "model-policy-embedding-probe")
    ]
    [
      "name = openai.astra;"
      "name = openai.sol;"
    ]
    [
      "\${openai.sol}.contextWindow = ${
        toString baseline.codex.modelOverrides.${baseline.openai.sol}.contextWindow
      };"
      "\${openai.sol}.contextWindow = 524288;"
    ]
    [
      "autoCompactPercent = ${toString baseline.codex.autoCompactPercent};"
      "autoCompactPercent = 60;"
    ]
    [
      "reasoningEffort = ${builtins.toJSON baseline.codex.reasoningEffort};"
      ''reasoningEffort = "medium";''
    ]
    [
      "name = \"\${anthropic.opus}[1m]\";"
      ''name = "model-policy-claude-probe";''
    ]
    [
      "prime.thinkingLevel = ${builtins.toJSON baseline.prime.thinkingLevel};"
      ''prime.thinkingLevel = "high";''
    ]
    [
      (builtins.toJSON baseline.recordings.asr.model)
      ''"asr probe's model"''
    ]
    [
      "geminiFlash = ${builtins.toJSON baseline.advisors.pal.reasoning};"
      ''geminiFlash = "model-policy-pal-reasoning";''
    ]
    [
      "partner = ${builtins.toJSON baseline.advisors.pal.partner};"
      ''partner = "model-policy-pal-partner";''
    ]
    [
      (builtins.toJSON baseline.anthropic.fable51)
      (builtins.toJSON "model-policy-validator")
    ]
    [
      ''max-output = "unconstrained";''
      "max-output = 16384;"
    ]
    [
      ''default-persona = "personal";''
      ''default-persona = "emacs";''
    ]
  ];
  changedSource = lib.foldl' (
    text: edit:
    assert builtins.length (lib.splitString (builtins.head edit) text) == 2;
    lib.replaceStrings [ (builtins.head edit) ] [ (builtins.elemAt edit 1) ] text
  ) source edits;
  policies = {
    inherit baseline;
    changed = import (builtins.toFile "changed-model-policy.nix" changedSource);
  };
  python = pkgs.python3.withPackages (packages: [ packages.pyyaml ]);
  fixtureSource = ./fixtures/model-policy-codex;
  fixtureCatalog = fixtureSource + "/codex-rs/models-manager/models.json";
  codexPackage.unwrappedPackage =
    (pkgs.writeShellScriptBin "codex" ''
      test "$*" = 'debug models --bundled'
      ${pkgs.jq}/bin/jq '.models |= map(. + {base_instructions: "fixture serialization"})' ${fixtureCatalog}
    '')
    // {
      src = fixtureSource;
    };
  rendererPkgs = pkgs // {
    agent-resources = "/model-policy-resources";
    pi-flag = "/model-policy-flag";
    pi-gallery.packages = lib.genAttrs [
      "pi-loop"
      "pi-gpt-fast-mode"
      "pi-provider-llama-swap"
      "pi-provider-omlx"
    ] (_: "/model-policy-package");
    recordings = "/model-policy-recordings";
  };
  selected = lib.genAttrs [
    "agents"
    "commands"
    "prompts"
    "skills"
    "hooks"
    "marketplaces"
    "settings"
    "mcpServers"
  ] (_: { });
  capture = pkgs.writeText "recordings-capture.py" ''
    import json
    import sys
    json.dump(sys.argv[1:], sys.stdout)
  '';
  renderCase =
    name: policy:
    let
      catalog = import ../../config/ai/catalog.nix {
        inherit lib;
        resources = rendererPkgs.agent-resources;
        models = policy;
      };
      common = {
        inherit selected;
        homeDirectory = "/model-policy-home";
        xdgConfigHome = "/model-policy-home/.config";
      };
      endpoints = catalog.localModelEndpointsByHost.hera;
      codex =
        (import ../../config/ai/renderers/codex.nix {
          inherit lib codexPackage;
          pkgs = rendererPkgs;
          models = policy;
        })
          (
            common
            // {
              profile = catalog.profiles.hera-codex;
              localModelEndpoints = endpoints;
            }
          );
      pi =
        (import ../../config/ai/renderers/pi.nix {
          inherit lib;
          pkgs = rendererPkgs;
          modelPolicy = policy;
        })
          (
            common
            // {
              profile = catalog.profiles.hera-pi // {
                hermesRoute = false;
              };
              passwordStoreDir = "/model-policy-unused-pass";
              gnupgHome = "/model-policy-unused-gpg";
              localModelEndpoints = endpoints;
              localModelDiscoveryEndpoints = catalog.piModelDiscoveryEndpoints;
            }
          );
      primeFor =
        localModelEndpoints:
        (import ../../config/ai/renderers/prime.nix {
          inherit lib;
          pkgs = rendererPkgs;
          modelPolicy = policy;
        })
          (
            common
            // {
              inherit localModelEndpoints;
              profile = catalog.profiles.hera-prime // {
                localModelRoutes = localModelEndpoints != null;
              };
            }
          );
      prime = primeFor endpoints;
      primeWithoutRoutes = primeFor null;
      claude =
        (import ../../config/ai/renderers/claude.nix {
          inherit lib;
          pkgs = rendererPkgs;
        })
          (
            common
            // {
              profile = catalog.profiles.hera-claude-personal;
              selected = selected // {
                settings.claude = catalog.items.settings.claude;
              };
            }
          );
      launchdFor =
        host:
        import ../../config/launchd.nix {
          inherit lib;
          pkgs = rendererPkgs;
          modelPolicy = policy;
          hostname = host;
          config.johnw = {
            host = (import ../../config/hosts.nix).capabilitiesFor { hostname = host; };
            omlxProxy.enable = false;
          };
        };
      recordingsScript = (launchdFor "hera").launchd.user.agents.recordings.script;
      script = pkgs.writeText "recordings-${name}.sh" (
        lib.replaceStrings
          [
            "${rendererPkgs.recordings}/bin/recordings"
          ]
          [ "${pkgs.python3}/bin/python3 ${capture}" ]
          recordingsScript
      );
      aliases = import ../../config/ai/agent-model-aliases.nix {
        inherit lib;
        models = policy;
      };
      route = catalog.recordingTranscriptionRoutesByHost.hera;
      agentCat =
        (import ../../config/ai/renderers/agent-cat.nix {
          inherit lib pkgs;
          modelPolicy = policy;
        })
          (builtins.removeAttrs common [ "selected" ]);
      json = pkgs.formats.json { };
      renderLib = import ../../config/ai/renderers/render-lib.nix {
        inherit lib;
        modelPolicy = policy;
      };
      modelPrompts = lib.mapAttrs (_: source: renderLib.renderModelText (builtins.readFile source)) {
        heavy = ../../config/ai/commands/heavy.md;
        review = ../../config/ai/commands/review-github-pr.md;
        forge = ../../config/ai/skills/forge/SKILL.md;
        validation = ../../config/ai/skills/validated-code-review/SKILL.md;
        wiggum = ../../config/ai/skills/wiggum/SKILL.md;
      };
    in
    assert !(builtins.hasAttr "recordings" (launchdFor "clio").launchd.user.agents);
    assert lib.hasInfix "${rendererPkgs.recordings}/bin/recordings" recordingsScript;
    assert
      !(builtins.tryEval (builtins.deepSeq (renderLib.renderModelText "@NIX_MODEL_UNKNOWN@") true))
      .success;
    assert renderLib.renderModelText "literal without model fields" == "literal without model fields";
    ''
      mkdir -p "$out/${name}"
      cp ${json.generate "${name}-policy.json" policy} "$out/${name}/policy.json"
      cp ${json.generate "${name}-aliases.json" aliases} "$out/${name}/aliases.json"
      cp ${json.generate "${name}-model-prompts.json" modelPrompts} "$out/${name}/prompts.json"
      cp ${agentCat.files.".config/agent-cat/routing.yaml".source} "$out/${name}/routing.yaml"
      cp ${
        json.generate "${name}-route.json" (route // { endpoint = endpoints.${route.provider}; })
      } "$out/${name}/route.json"
      cp ${codex.files.".config/codex/nix-managed.config.toml".source} "$out/${name}/codex.toml"
      cp ${
        codex.files.".config/codex/nix-managed-model-catalog.json".source
      } "$out/${name}/codex-catalog.json"
      cp ${pi.files.".config/pi/agent/models.json".source} "$out/${name}/pi.json"
      cp ${
        pi.files.".config/pi/agent/extensions/pi-gpt-fast-mode/config.json".source
      } "$out/${name}/fast-mode.json"
      cp ${prime.files.".prime/agent/models.json".source} "$out/${name}/prime.json"
      cp ${
        primeWithoutRoutes.files.".prime/agent/managed-settings.json".source
      } "$out/${name}/prime-settings.json"
      cp ${
        claude.files.".config/claude/personal/nix-managed-settings.json".source
      } "$out/${name}/claude.json"
      ${pkgs.bash}/bin/bash ${script} > "$out/${name}/recordings-argv.json"
    '';
in
assert baseline.advisors.pal.reasoning == "gemini-3.8-flash";
assert
  baseline.advisors.validation == [
    "claude-fable-5-1"
    "gpt-6-astra"
  ];
pkgs.runCommand "model-policy-propagation" { } ''
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList renderCase policies)}
  ${python}/bin/python3 - "$out" ${fixtureCatalog} <<'PY'
  import json
  import shlex
  import sys
  import tomllib
  import yaml
  from pathlib import Path

  root = Path(sys.argv[1])
  source = json.loads(Path(sys.argv[2]).read_text())
  for name in ("baseline", "changed"):
      directory = root / name
      def load(filename):
          return json.loads((directory / filename).read_text())
      policy = load("policy.json")
      routing = yaml.safe_load((directory / "routing.yaml").read_text())
      assert routing == policy["agentCat"] | {"version": 2, "secrets": {}}
      assert routing["models"]["claude-fable"]["select"] == [{"exact": "claude-fable-5-1[1m]"}]
      assert routing["models"]["claude-opus"]["select"] == [{"exact": "opus[1m]"}]
      assert routing["models"]["codex-sol"]["select"] == [{"exact": policy["openai"]["sol"]}]
      assert routing["models"]["droid-gemini-3.1-pro"]["select"] == [{"exact": "gemini-3.1-pro-preview"}]
      assert routing["engines"]["deck-nix"]["backend"] == "deck:nix"
      assert set(routing["engines"]) == {"claude", "codex", "droid", "deck-nix"}
      qwen = policy["omlx"]["primary"]
      qwen_families = [
          model
          for model in policy["emacs"]["models"]
          if any(instance.get("name") == qwen["name"] for instance in model["instances"])
      ]
      assert len(qwen_families) == 1
      assert qwen_families[0]["instances"] == [
          {
              "hostnames": [
                  provider.removeprefix("omlx-") for provider in qwen["providers"]
              ],
              "name": qwen["name"],
              "provider": "omlx",
          }
      ]
      overrides = policy["codex"]["modelOverrides"]
      nixos = policy["nixos"]
      assert nixos["llm"]["primary"]["name"] == qwen["name"]
      assert nixos["llm"]["fast"]["name"] == qwen["name"]
      assert nixos["llm"]["reasoning"]["name"] == policy["omlx"]["reasoning"]["name"]
      assert nixos["embedding"]["primary"]["name"] == policy["embeddings"]["omlx"]
      for filename, provider in (("pi.json", "omlx-hera"), ("prime.json", "omlx")):
          providers = load(filename)["providers"]
          assert providers["openai-codex"]["modelOverrides"] == overrides
          assert providers[provider]["modelOverrides"][qwen["name"]]["contextWindow"] == qwen["contextWindow"]
          assert providers[provider]["modelOverrides"][qwen["name"]]["maxTokens"] == qwen["maxTokens"]
      assert load("fast-mode.json") == policy["pi"]["fastMode"]
      assert load("prime-settings.json")["defaultThinkingLevel"] == policy["prime"]["thinkingLevel"]
      aliases = load("aliases.json")
      assert aliases["aliases"] == policy["agentAliases"]["aliases"]
      assert aliases["defaultAlias"] == policy["agentAliases"]["default"]
      claude = load("claude.json")
      assert claude["model"] == policy["claude"]["name"]
      assert claude["effortLevel"] == policy["claude"]["effort"]
      assert claude["env"]["CLAUDE_CODE_MAX_OUTPUT_TOKENS"] == str(policy["claude"]["maxOutputTokens"])
      assert claude["env"]["ANTHROPIC_DEFAULT_HAIKU_MODEL"] == policy["claude"]["haiku"]
      assert claude["env"]["CLAUDE_CODE_SUBAGENT_MODEL"] == policy["claude"]["subagent"]
      native = load("codex-catalog.json")
      expected = dict(source)
      expected["models"] = []
      for model in source["models"]:
          projected = model | {"base_instructions": "fixture serialization"}
          if model["slug"] in overrides:
              projected["context_window"] = overrides[model["slug"]]["contextWindow"]
          expected["models"].append(projected)
      assert native == expected
      with (directory / "codex.toml").open("rb") as stream:
          codex = tomllib.load(stream)
      assert codex["model"] == policy["codex"]["name"]
      assert codex["model_reasoning_effort"] == policy["codex"]["reasoningEffort"]
      assert codex["model_auto_compact_token_limit"] == overrides[codex["model"]]["contextWindow"] * policy["codex"]["autoCompactPercent"] // 100
      assert codex["profiles"]["omlx"]["model"] == qwen["name"]
      route = load("route.json")
      assert {key: route[key] for key in ("model", "provider")} == policy["recordings"]["llm"]
      assert route["model"] == qwen["name"]
      argv = load("recordings-argv.json")
      assert argv[argv.index("--llm-model") + 1] == route["model"]
      assert argv[argv.index("--llm-url") + 1] == route["endpoint"]
      assert shlex.split(argv[argv.index("--asr-command") + 1]) == [
          "mlx-speech", "asr", "--model", policy["recordings"]["asr"]["model"],
          "--language", policy["recordings"]["asr"]["language"], "--audio"
      ]
      prompts = load("prompts.json")
      assert all("@NIX_MODEL_" not in text for text in prompts.values())
      for prompt in ("heavy", "review", "forge", "wiggum"):
          assert policy["advisors"]["pal"]["reasoning"] in prompts[prompt]
          assert policy["advisors"]["pal"]["partner"] in prompts[prompt]
      assert "MODELS: " + ", ".join(policy["advisors"]["validation"]) in prompts["validation"]
      assert " or ".join(policy["advisors"]["forge"]) in prompts["forge"]
      print(f"{name}: model policy reaches generated clients, routing, prompts and recordings argv")
  PY
''
