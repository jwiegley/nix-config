{
  pkgs,
  src,
  agentResources,
  aiFlake,
  homeManagerLib,
  piGallery,
  inputs,
  testPkgsFor,
}:

let
  common = import ./home-manager-contract-common.nix {
    inherit
      pkgs
      src
      agentResources
      aiFlake
      homeManagerLib
      piGallery
      inputs
      testPkgsFor
      ;
  };

  # Pure catalog and renderer evaluation: no Home Manager configuration is
  # evaluated here, which is what keeps this check cheap.
  checks =
    common.contractInlineChecks
    ++ common.profileChecks
    ++ common.reachabilityChecks
    ++ common.rendererChecks
    ++ common.positronPyTorchSkillSelectionChecks
    ++ common.promptdeployReconciliationChecks;
in
assert builtins.deepSeq checks true;

pkgs.runCommand "ai-home-manager-catalog-renderers"
  {
    nativeBuildInputs = [
      pkgs.findutils
      pkgs.jq
      common.assetCheckPython
    ];
  }
  ''
    python3 "${src}/test/ai/statusline-command-test.py"

    test -f "${common.piExtensionSources.auto-compact-resume}"
    test -f "${common.piExtensionSources.nix-gallery}"
    test -f "${common.piPkgs.pi-gallery}/share/pi-gallery/projection.json"
    test -f "${common.piExtensionSources.pi-mcp-adapter}/package.json"
    test -f "${common.piExtensionSources.pi-mcp-adapter}/index.ts"
    test -d "${common.piExtensionSources.pi-mcp-adapter}/node_modules/@modelcontextprotocol/sdk"
    test -d "${common.piExtensionSources.pi-mcp-adapter}/node_modules/zod"
    test -f "${common.piExtensionSources.pi-quiet}/package.json"
    test -f "${common.piExtensionSources.pi-quiet}/src/index.ts"

    python3 -I - "${common.rendererDocumentManifest}" <<'PY'
    import json
    import subprocess
    import sys
    import tomllib
    from pathlib import Path

    records = json.loads(Path(sys.argv[1]).read_text())
    errors = []

    for record in records:
        label = record["label"]
        document = record["path"]
        if isinstance(document, dict):
            text = document["inlineText"]
        else:
            path = Path(document)
            if not path.is_file():
                errors.append(f"{label}: not a regular file: {path}")
                continue
            text = path.read_text()

        if "sourceDirectory" in record:
            source_directory = Path(record["sourceDirectory"])
            if not source_directory.is_dir():
                errors.append(
                    f"{label}: projection source is not a directory: {source_directory}"
                )
            elif record.get("explicitOnly"):
                if {entry.name for entry in source_directory.iterdir()} != {"SKILL.md", "agents"}:
                    errors.append(f"{label}: explicit projection has unexpected entries")
                policy = source_directory / "agents" / "openai.yaml"
                if not policy.is_file() or policy.read_text() != (
                    "policy:\n  allow_implicit_invocation: false\n"
                ):
                    errors.append(f"{label}: explicit-only policy is missing or incorrect")
            elif {entry.name for entry in source_directory.iterdir()} != {"SKILL.md"}:
                errors.append(f"{label}: projection directory must contain only SKILL.md")
        for fragment in record.get("forbidden", []):
            if fragment in text:
                errors.append(f"{label}: contains forbidden fragment {fragment!r}")

        if record["kind"] == "json":
            parsed = subprocess.run(
                ["jq", "-e", "."],
                check=False,
                capture_output=True,
                input=text,
                text=True,
            )
            if parsed.returncode:
                errors.append(f"{label}: jq rejected JSON: {parsed.stderr.strip()}")
                continue
            actual = json.loads(text)
            if not record.get("structuralOnly") and actual != record["expected"]:
                errors.append(f"{label}: semantic JSON mismatch")

            catalog_contract = record.get("catalogContract")
            if catalog_contract:
                source_path = Path(catalog_contract["sourcePath"])
                try:
                    source_catalog = json.loads(source_path.read_text())
                except (OSError, json.JSONDecodeError) as error:
                    errors.append(f"{label}: invalid locked source catalog: {error}")
                    continue

                source_models = (
                    source_catalog.get("models")
                    if isinstance(source_catalog, dict)
                    else None
                )
                actual_models = actual.get("models") if isinstance(actual, dict) else None
                if not isinstance(source_models, list):
                    errors.append(f"{label}: locked source catalog has no models list")
                    continue
                if not isinstance(actual_models, list):
                    errors.append(f"{label}: rendered catalog has no models list")
                    continue

                native_slug = catalog_contract["nativeSlug"]
                native_models = [
                    model
                    for model in source_models
                    if isinstance(model, dict) and model.get("slug") == native_slug
                ]
                if len(native_models) != 1:
                    errors.append(
                        f"{label}: locked source catalog contains {len(native_models)} "
                        f"native {native_slug!r} models, expected exactly one"
                    )
                if len(actual_models) != len(source_models) + 1:
                    errors.append(
                        f"{label}: rendered catalog model count is {len(actual_models)}, "
                        f"expected {len(source_models) + 1}"
                    )

                expected_models = catalog_contract["expectedModels"]
                expected_slugs = {model["slug"] for model in expected_models}
                metadata_keys = tuple(expected_models[0])
                actual_sol_models = [
                    {key: model.get(key) for key in metadata_keys}
                    for model in actual_models
                    if isinstance(model, dict) and model.get("slug") in expected_slugs
                ]
                if actual_sol_models != expected_models:
                    errors.append(f"{label}: Sol model catalog metadata mismatch")
        elif record["kind"] == "toml":
            try:
                actual = tomllib.loads(text)
            except tomllib.TOMLDecodeError as error:
                errors.append(f"{label}: tomllib rejected TOML: {error}")
                continue
            if actual != record["expected"]:
                errors.append(f"{label}: semantic TOML mismatch")
        elif record["kind"] == "text":
            if text != record["expectedText"]:
                errors.append(f"{label}: exact text mismatch")
        elif record["kind"] == "frontmatter":
            if text.startswith("---\n"):
                try:
                    metadata_text, body = text[4:].split("\n---\n", 1)
                    metadata = json.loads(metadata_text)
                except (ValueError, json.JSONDecodeError) as error:
                    errors.append(f"{label}: invalid frontmatter: {error}")
                    continue
            else:
                metadata = {}
                body = text
            if metadata != record["expectedMetadata"]:
                errors.append(f"{label}: semantic frontmatter mismatch")
            if body != record["expectedBody"]:
                errors.append(f"{label}: exact body mismatch")
        else:
            errors.append(f"{label}: unknown fixture kind {record['kind']!r}")

    if errors:
        print("ai-home-manager-catalog-renderers: renderer document check failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        raise SystemExit(1)
    PY

    python3 -I - "${src}/config/ai" <<'PY'
    import os
    import re
    import stat
    import sys
    import yaml
    from pathlib import Path

    root = Path(sys.argv[1])

    missing = [
        category
        for category in ("agents", "commands", "skills", "prompts")
        if not (root / category).is_dir()
    ]
    missing.extend(
        name
        for name in (
            "catalog.nix",
            "model-policy.nix",
            "model-registry.json",
            "model-sync.nix",
            "models.nix",
            "preflight.nix",
        )
        if not (root / name).is_file()
    )
    statusline = root / "statusline-command.sh"
    if not statusline.is_file():
        missing.append("statusline")
    if missing:
        print("ai-home-manager-catalog-renderers: missing asset categories:", file=sys.stderr)
        for category in missing:
            print(f"  {category}", file=sys.stderr)
        raise SystemExit(1)

    errors = []
    if root.is_symlink():
        errors.append("config/ai must not be a symlink")

    paths = []
    for directory, directories, files in os.walk(root, followlinks=False):
        directories.sort()
        files.sort()
        base = Path(directory)
        paths.extend(base / name for name in directories)
        paths.extend(base / name for name in files)

    resolved_root = root.resolve(strict=True)
    canonical_roots = {
        "agents",
        "commands",
        "skills",
        "prompts",
        "statusline-command.sh",
    }
    asset_paths = [
        path
        for path in paths
        if path.relative_to(root).parts[0] in canonical_roots
    ]

    for path in asset_paths:
        mode = path.lstat().st_mode
        if not (stat.S_ISDIR(mode) or stat.S_ISREG(mode) or stat.S_ISLNK(mode)):
            errors.append(f"unsupported file type: {path.relative_to(root)}")

    for path in paths:
        if not path.is_symlink():
            continue
        try:
            target = path.resolve(strict=True)
            target.relative_to(resolved_root)
        except (OSError, RuntimeError, ValueError) as error:
            errors.append(f"dangling or escaping symlink: {path.relative_to(root)}: {error}")

    if errors:
        print("ai-home-manager-catalog-renderers: asset check failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        raise SystemExit(1)

    for path in paths:
        name = path.name.lower()
        if (
            name.startswith(".promptdeploy")
            or name.startswith(".env")
            or "manifest" in name
            or "receipt" in name
            or (name.endswith(".json") and "selector" in name)
        ):
            errors.append(f"forbidden committed artifact: {path.relative_to(root)}")

    renderers = root / "renderers"
    if not renderers.is_dir():
        errors.append("not a renderer directory: renderers")
    else:
        required_renderers = {
            "claude.nix",
            "codex.nix",
            "droid.nix",
            "merge-files.nix",
            "opencode.nix",
            "pi.nix",
        }
        for name in required_renderers:
            if not (renderers / name).is_file():
                errors.append(f"not a regular renderer: renderers/{name}")

    for category in ("agents", "commands", "prompts"):
        entries = list((root / category).iterdir())
        if not entries:
            errors.append(f"empty asset category: {category}")
        for entry in entries:
            if entry.suffix.lower() != ".md" or not entry.is_file():
                errors.append(f"not a Markdown asset: {entry.relative_to(root)}")

    skill_entries = sorted((root / "skills").iterdir(), key=lambda path: path.name)
    if not skill_entries:
        errors.append("empty asset category: skills")
    for skill in skill_entries:
        if not skill.is_dir():
            errors.append(f"not a skill tree: {skill.relative_to(root)}")
            continue

        skill_document = skill / "SKILL.md"
        if not skill_document.is_file():
            errors.append(f"missing SKILL.md: {skill.relative_to(root)}")
            continue

        try:
            lines = skill_document.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeError) as error:
            errors.append(
                f"cannot read UTF-8 skill {skill_document.relative_to(root)}: {error}"
            )
            continue
        if not lines or lines[0].strip() != "---":
            errors.append(f"missing frontmatter: {skill_document.relative_to(root)}")
            continue
        try:
            end = next(
                index
                for index, line in enumerate(lines[1:], start=1)
                if line.strip() == "---"
            )
        except StopIteration:
            errors.append(f"unterminated frontmatter: {skill_document.relative_to(root)}")
            continue
        try:
            metadata = yaml.safe_load("\n".join(lines[1:end]))
        except yaml.YAMLError as error:
            errors.append(
                f"malformed YAML frontmatter: {skill_document.relative_to(root)}: {error}"
            )
            continue
        if not isinstance(metadata, dict):
            errors.append(
                f"frontmatter is not a mapping: {skill_document.relative_to(root)}"
            )
            continue

        name = metadata.get("name")
        description = metadata.get("description")
        if not isinstance(name, str) or not name.strip():
            errors.append(f"missing skill name: {skill_document.relative_to(root)}")
        elif name != skill.name:
            errors.append(
                f"skill name {name!r} does not match directory {skill.name!r}: "
                f"{skill_document.relative_to(root)}"
            )
        if not isinstance(description, str) or not description.strip():
            errors.append(f"missing skill description: {skill_document.relative_to(root)}")

    if not os.access(statusline, os.X_OK):
        errors.append("statusline-command.sh is not executable")

    deployment_field = re.compile(
        r"(?:^|[,{])\s*['\"]?(only|except|droid_deploy)['\"]?\s*:",
        re.MULTILINE,
    )
    for path in paths:
        if path.suffix.lower() != ".md" or not path.is_file():
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeError) as error:
            errors.append(f"cannot read UTF-8 Markdown {path.relative_to(root)}: {error}")
            continue
        if not lines or lines[0].strip() != "---":
            continue
        try:
            end = next(
                index
                for index, line in enumerate(lines[1:], start=1)
                if line.strip() == "---"
            )
        except StopIteration:
            errors.append(f"unterminated frontmatter: {path.relative_to(root)}")
            continue
        match = deployment_field.search("\n".join(lines[1:end]))
        if match:
            errors.append(
                f"deployment field {match.group(1)!r}: {path.relative_to(root)}"
            )

    if errors:
        print("ai-home-manager-catalog-renderers: asset check failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        raise SystemExit(1)
    PY

    touch "$out"
  ''
