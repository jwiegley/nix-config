{
  pkgs,
  superpowers ? null,
  ponytail ? null,
  translate-tool ? null,
  gitSurgeonSource ? null,
}:

let
  inherit (pkgs) lib;

  superpowersSkills = [
    "brainstorming"
    "dispatching-parallel-agents"
    "executing-plans"
    "finishing-a-development-branch"
    "receiving-code-review"
    "requesting-code-review"
    "subagent-driven-development"
    "systematic-debugging"
    "test-driven-development"
    "using-git-worktrees"
    "using-superpowers"
    "verification-before-completion"
    "writing-plans"
    "writing-skills"
  ];

  ponytailSkills = [
    "ponytail"
    "ponytail-review"
    "ponytail-audit"
    "ponytail-debt"
    "ponytail-gain"
    "ponytail-help"
  ];

  expectedSkills =
    superpowersSkills
    ++ ponytailSkills
    ++ [
      "git-surgeon"
      "translate-en"
    ];

  resources = pkgs.agent-resources;
  haveSources =
    superpowers != null && ponytail != null && translate-tool != null && gitSurgeonSource != null;

  expectedPins = [
    {
      name = "superpowers revision";
      actual = superpowers.rev or null;
      expected = "d884ae04edebef577e82ff7c4e143debd0bbec99";
    }
    {
      name = "superpowers NAR hash";
      actual = superpowers.narHash or null;
      expected = "sha256-kHdQ9e44doBk2yYW88tMSCqVG8ycYcvJSZlrIziXhpA=";
    }
    {
      name = "ponytail revision";
      actual = ponytail.rev or null;
      expected = "16f29800fd2681bdf24f3eb4ccffe38be3baec6b";
    }
    {
      name = "ponytail NAR hash";
      actual = ponytail.narHash or null;
      expected = "sha256-Y7d4s7uqjH6IbEXhqAiQ+yaxr6iiGcv2X64LuMtG1T8=";
    }
    {
      name = "translate-tool revision";
      actual = translate-tool.rev or null;
      expected = "bffdb7ba3e5db603ea1390fee555354c1d45d642";
    }
    {
      name = "translate-tool NAR hash";
      actual = translate-tool.narHash or null;
      expected = "sha256-P27Hvn8p1+BN8z6g/aFk91BFtL9SMQiMNFYayKn5xyY=";
    }
  ];

  badPins = builtins.filter (pin: pin.actual != pin.expected) expectedPins;
  badPinMessage = lib.concatMapStringsSep ", " (
    pin: "${pin.name}: expected ${pin.expected}, got ${toString pin.actual}"
  ) badPins;

  expectedSkillArgs = lib.escapeShellArgs expectedSkills;
  superpowersSkillArgs = lib.escapeShellArgs superpowersSkills;
  ponytailSkillArgs = lib.escapeShellArgs ponytailSkills;

  copySuperpowersExpected = lib.concatMapStringsSep "\n" (name: ''
    copy_expected_tree ${lib.escapeShellArg "${superpowers}/skills/${name}"} "$expected/${name}"
    cp -a -- ${lib.escapeShellArg "${superpowers}/LICENSE"} "$expected/${name}/LICENSE"
    chmod --reference=${lib.escapeShellArg "${superpowers}/skills/${name}"} "$expected/${name}"
  '') superpowersSkills;

  copyPonytailExpected = lib.concatMapStringsSep "\n" (name: ''
    copy_expected_tree ${lib.escapeShellArg "${ponytail}/skills/${name}"} "$expected/${name}"
    chmod --reference=${lib.escapeShellArg "${ponytail}/skills/${name}"} "$expected/${name}"
  '') ponytailSkills;
in
assert resources != null;
if !haveSources then
  throw "agent-resources check requires all pinned source roots"
else if badPins != [ ] then
  throw "agent-resources source pin mismatch: ${badPinMessage}"
else if toString gitSurgeonSource != "/nix/store/akkhqhkkvwxm9y06g8zwp9s0hbc4xii8-source" then
  throw "current ai-nix git-surgeon source does not match the frozen promptdeploy source"
else
  pkgs.runCommand "agent-resources-check"
    {
      nativeBuildInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
      ];
    }
    ''
      set -euo pipefail

      actual=${resources}/share/agent-resources/skills
      expected="$TMPDIR/expected"
      mkdir -p "$expected"

      fail() {
        printf 'agent-resources check: %s\n' "$*" >&2
        exit 1
      }

      copy_expected_tree() {
        source_tree=$1
        destination=$2

        [ -d "$source_tree" ] && [ ! -L "$source_tree" ] \
          || fail "invalid source skill tree: $source_tree"
        [ ! -e "$destination" ] && [ ! -L "$destination" ] \
          || fail "duplicate expected skill destination: $destination"
        mkdir "$destination"
        cp -a -- "$source_tree"/. "$destination"/
        chmod u+w "$destination"
      }

      validate_tree() {
        tree=$1
        [ -d "$tree" ] && [ ! -L "$tree" ] || fail "invalid tree root: $tree"
        canonical_tree=$(realpath -e -- "$tree")

        while IFS= read -r -d "" path; do
          if [ -L "$path" ]; then
            target=$(readlink -- "$path")
            [ -n "$target" ] || fail "empty symlink target: $path"
            case "$target" in
              /*) fail "absolute symlink: $path -> $target" ;;
            esac
            [ -e "$path" ] || fail "dangling symlink: $path -> $target"
            resolved=$(realpath -e -- "$path")
            case "$resolved" in
              "$canonical_tree" | "$canonical_tree"/*) ;;
              *) fail "escaping symlink: $path -> $target" ;;
            esac
          elif [ ! -d "$path" ] && [ ! -f "$path" ]; then
            fail "special file in skill tree: $path"
          fi
        done < <(find -P "$tree" -mindepth 1 -print0)
      }

      write_manifest() {
        tree=$1
        output=$2
        : >"$output"
        validate_tree "$tree"

        while IFS= read -r -d "" path; do
          relative=''${path#"$tree"/}
          mode=$(stat -c '%a' -- "$path")
          target=
          digest=

          if [ -L "$path" ]; then
            type=l
            target=$(readlink -- "$path")
          elif [ -d "$path" ]; then
            type=d
          elif [ -f "$path" ]; then
            type=f
            digest=$(sha256sum -- "$path")
            digest=''${digest%% *}
          else
            fail "unsupported file type: $path"
          fi

          printf '%s\0%s\0%s\0%s\0%s\0' \
            "$relative" "$type" "$mode" "$target" "$digest" >>"$output"
        done < <(find -P "$tree" -mindepth 1 -print0 | sort -z)
      }

      ${copySuperpowersExpected}
      ${copyPonytailExpected}
      copy_expected_tree \
        ${lib.escapeShellArg "${gitSurgeonSource}/skills/git-surgeon"} \
        "$expected/git-surgeon"
      cp -a -- ${lib.escapeShellArg "${gitSurgeonSource}/LICENSE"} \
        "$expected/git-surgeon/LICENSE"
      chmod --reference=${lib.escapeShellArg "${gitSurgeonSource}/skills/git-surgeon"} \
        "$expected/git-surgeon"
      copy_expected_tree ${lib.escapeShellArg "${translate-tool}/skill"} \
        "$expected/translate-en"
      rm -- "$expected/translate-en/GLOSSARY.csv"
      cp -a -- ${lib.escapeShellArg "${translate-tool}/glossary.csv"} \
        "$expected/translate-en/GLOSSARY.csv"
      chmod --reference=${lib.escapeShellArg "${translate-tool}/skill"} \
        "$expected/translate-en"

      [ -d "$actual" ] && [ ! -L "$actual" ] \
        || fail "missing regular skills root: $actual"

      printf '%s\0' ${expectedSkillArgs} | sort -z >"$TMPDIR/expected-names"
      if [ "$(tr '\0' '\n' <"$TMPDIR/expected-names" | uniq -d | wc -l)" -ne 0 ]; then
        fail "duplicate name in the independent expected skill list"
      fi
      find -P "$actual" -mindepth 1 -maxdepth 1 -printf '%f\0' \
        | sort -z >"$TMPDIR/actual-names"
      cmp "$TMPDIR/expected-names" "$TMPDIR/actual-names" \
        || fail "skill name set differs from the expected 22 names"

      for name in ${expectedSkillArgs}; do
        [ -d "$actual/$name" ] && [ ! -L "$actual/$name" ] \
          || fail "invalid skill root: $name"
        [ -f "$actual/$name/SKILL.md" ] && [ ! -L "$actual/$name/SKILL.md" ] \
          || fail "missing regular SKILL.md: $name"
      done

      for name in ${superpowersSkillArgs} git-surgeon; do
        [ -f "$actual/$name/LICENSE" ] && [ ! -L "$actual/$name/LICENSE" ] \
          || fail "missing regular injected LICENSE: $name"
      done

      [ -f "$actual/translate-en/GLOSSARY.csv" ] \
        && [ ! -L "$actual/translate-en/GLOSSARY.csv" ] \
        || fail "translate-en glossary was not materialized"

      test "$(sha256sum ${lib.escapeShellArg "${gitSurgeonSource}/skills/git-surgeon/SKILL.md"} | cut -d' ' -f1)" \
        = 086445cd0424c46022c7c23912c82ebb43d168e11b3a13141669149bdba6f8bc
      test "$(sha256sum ${lib.escapeShellArg "${gitSurgeonSource}/LICENSE"} | cut -d' ' -f1)" \
        = dfc0be306ac621b63914bf0f4854538a2e0a8d09ad24f20e7edd9a80ece241b2
      test "$(sha256sum ${lib.escapeShellArg "${translate-tool}/skill/SKILL.md"} | cut -d' ' -f1)" \
        = f26ff06e43b9d99e96876cbd567a7f6d8585983b0a550b97ef5e672f294790fb
      test "$(sha256sum ${lib.escapeShellArg "${translate-tool}/glossary.csv"} | cut -d' ' -f1)" \
        = 8eab769223267b8b8cded5ba62f7a4250dfcf25d94d35cffd7e360354b3e9523

      for name in ${ponytailSkillArgs}; do
        if find -P "$actual/$name" -mindepth 1 \
          \( -path '*/hooks/*' -o -name '*runtime*' -o -name '*statusline*' \
             -o -name '*bundle-receipt*' -o -path '*/.opencode/*' \
             -o -path '*/plugins/*' -o -path '*/commands/*' \
             -o -path '*/pi-extension/*' -o -path '*/ponytail-mcp/*' \) \
          -print -quit | grep -q .; then
          fail "excluded Ponytail payload appears under $name"
        fi
      done

      write_manifest "$expected" "$TMPDIR/expected.manifest"
      write_manifest "$actual" "$TMPDIR/actual.manifest"
      cmp "$TMPDIR/expected.manifest" "$TMPDIR/actual.manifest" \
        || fail "framed path/type/mode/link/content manifests differ"

      mkdir -p "$out"
      printf '%s\n' ${expectedSkillArgs} >"$out/skills.txt"
    ''
