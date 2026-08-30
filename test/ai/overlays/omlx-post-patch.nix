{
  coreutils,
  gnugrep,
  omlx,
  runCommand,
}:

let
  sources = import ../../../packages/source-catalog.nix "ai";
in
runCommand "omlx-post-patch"
  {
    nativeBuildInputs = [
      coreutils
      gnugrep
    ];
  }
  ''
    set -euo pipefail

    fail() {
      echo "omlx postPatch test: $1" >&2
      exit 1
    }

    prepare_case() {
      case_dir="$work/$1"
      mkdir -p "$case_dir"
      cp -R ${omlx.src}/. "$case_dir/"
      chmod -R u+w "$case_dir"
      printf '\n# omlx-post-patch-sentinel\n' >> "$case_dir/pyproject.toml"
    }

    current_ddgs_coordinate() {
      local -a coordinates
      mapfile -t coordinates < <(grep -Eo '"ddgs[^" ]*"' "$case_dir/pyproject.toml")
      [ "''${#coordinates[@]}" -eq 1 ] \
        || fail "fixture must contain exactly one DDGS coordinate"
      printf '%s\n' "''${coordinates[0]}"
    }

    replace_current_ddgs() {
      current=$(current_ddgs_coordinate)
      substituteInPlace "$case_dir/pyproject.toml" \
        --replace-fail "$current" "$1"
    }

    apply_post_patch() (
      set -euo pipefail
      cd "$1"
      ${omlx.postPatch}
    )

    expect_rejected() {
      label=$1
      diagnostic=$2
      set +e
      apply_post_patch "$case_dir" >"$work/$label.stdout" 2>"$work/$label.stderr"
      status=$?
      set -e
      [ "$status" -ne 0 ] || fail "$label unexpectedly succeeded"
      grep -Fq "$diagnostic" "$work/$label.stderr" \
        || fail "$label did not report its source-coordinate diagnostic"
    }

    work="$TMPDIR/omlx-post-patch-cases"
    mkdir -p "$work"

    prepare_case accepted
    apply_post_patch "$case_dir"
    grep -Fq '"mlx==${sources.omlx-mlx.version}"' "$case_dir/pyproject.toml" \
      || fail "exact oMLX MLX requirement changed"
    grep -Fq '"ddgs==${sources.omlx-ddgs.version}"' "$case_dir/pyproject.toml" \
      || fail "exact oMLX DDGS requirement changed"
    grep -Fq '# omlx-post-patch-sentinel' "$case_dir/pyproject.toml" \
      || fail "postPatch changed unrelated source"
    if grep -Eq '"(mlx-lm|mlx-embeddings|mlx-vlm|dflash-mlx|mlx-audio)[^\"]* @ git\+' "$case_dir/pyproject.toml"; then
      fail "a direct dependency reference survived postPatch"
    fi

    prepare_case alternate-ddgs
    replace_current_ddgs '"ddgs==0.0.1"'
    expect_rejected alternate-ddgs "must declare exactly ddgs==${sources.omlx-ddgs.version}"

    prepare_case missing-ddgs
    replace_current_ddgs '"not-ddgs==0.0.1"'
    expect_rejected missing-ddgs "exactly 1 bare ddgs==${sources.omlx-ddgs.version} requirements, found 0"

    prepare_case duplicate-ddgs
    current=$(current_ddgs_coordinate)
    duplicate="$current,"$'\n    '"$current"
    replace_current_ddgs "$duplicate"
    expect_rejected duplicate-ddgs "exactly 1 bare ddgs==${sources.omlx-ddgs.version} requirements, found 2"

    prepare_case composite-ddgs
    replace_current_ddgs '"ddgs==${sources.omlx-ddgs.version},!=0.0.0"'
    expect_rejected composite-ddgs "must declare exactly ddgs==${sources.omlx-ddgs.version}"

    prepare_case marked-ddgs
    replace_current_ddgs '"ddgs==${sources.omlx-ddgs.version};python_version<'"'"'3.14'"'"'"'
    expect_rejected marked-ddgs "must declare exactly ddgs==${sources.omlx-ddgs.version}"

    prepare_case mlx-mismatch
    substituteInPlace "$case_dir/pyproject.toml" \
      --replace-fail '"mlx==${sources.omlx-mlx.version}"' '"mlx==0.0.1"'
    expect_rejected mlx-mismatch "must declare exactly mlx==${sources.omlx-mlx.version}"

    prepare_case mlx-lm-mismatch
    substituteInPlace "$case_dir/pyproject.toml" \
      --replace-fail '${sources.mlx-lm.source.args.rev}' \
      '0000000000000000000000000000000000000000'
    expect_rejected mlx-lm-mismatch "exact mlx-lm source coordinate"

    prepare_case mlx-embeddings-mismatch
    substituteInPlace "$case_dir/pyproject.toml" \
      --replace-fail '${sources.omlx-mlx-embeddings.source.args.rev}' \
      '0000000000000000000000000000000000000000'
    expect_rejected mlx-embeddings-mismatch "exact mlx-embeddings source coordinate"

    prepare_case dflash-mismatch
    substituteInPlace "$case_dir/pyproject.toml" \
      --replace-fail '${sources.dflash-mlx.source.args.rev}' \
      '0000000000000000000000000000000000000000'
    expect_rejected dflash-mismatch "exact dflash-mlx source coordinate"

    prepare_case mlx-audio-mismatch
    substituteInPlace "$case_dir/pyproject.toml" \
      --replace-fail '${sources.omlx-mlx-audio.source.args.rev}' \
      '0000000000000000000000000000000000000000'
    expect_rejected mlx-audio-mismatch "exact mlx-audio source coordinate"

    touch "$out"
  ''
