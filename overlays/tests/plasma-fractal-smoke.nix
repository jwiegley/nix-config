{
  coreutils,
  git,
  gnugrep,
  plasma-fractal,
  plasma-wiki,
  runCommand,
}:

runCommand "plasma-fractal-smoke"
  {
    nativeBuildInputs = [
      coreutils
      gnugrep
    ];
  }
  ''
    set -euo pipefail

    export HOME="$TMPDIR/home"
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_CONFIG_HOME="$HOME/.config"
    export TMUX_TMPDIR="$TMPDIR/tmux"
    export COLUMNS=120
    mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$TMUX_TMPDIR"

    clean_path="${plasma-fractal}/bin:${plasma-wiki}/bin"
    run_fractal() {
      env -i \
        HOME="$HOME" \
        XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
        TMUX_TMPDIR="$TMUX_TMPDIR" \
        COLUMNS="$COLUMNS" \
        OFFLINE_MODE=true \
        PATH="$clean_path" \
        TERM=xterm-256color \
        ${plasma-fractal}/bin/fractal "$@"
    }
    run_wiki() {
      env -i \
        HOME="$HOME" \
        XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
        OFFLINE_MODE=true \
        PATH="$clean_path" \
        TERM=xterm-256color \
        ${plasma-wiki}/bin/wiki "$@"
    }

    test "$(run_fractal --version)" = "1.0.0"
    run_fractal --help > "$TMPDIR/fractal-help.txt"
    run_wiki --help > "$TMPDIR/wiki-help.txt"
    test -s "$TMPDIR/fractal-help.txt"
    test -s "$TMPDIR/wiki-help.txt"

    test -f ${plasma-fractal}/share/skills/fractal/SKILL.md
    test -f ${plasma-fractal}/share/skills/fractal/agents/openai.yaml
    test -f ${plasma-wiki}/share/skills/wiki/SKILL.md
    test -f ${plasma-wiki}/share/skills/wiki/agents/openai.yaml

    fractal_roots=(${plasma-fractal}/lib/python*/site-packages/fractal)
    wiki_roots=(${plasma-wiki}/lib/python*/site-packages/wiki)
    test "''${#fractal_roots[@]}" -eq 1
    test "''${#wiki_roots[@]}" -eq 1
    fractal_root="''${fractal_roots[0]}"
    wiki_root="''${wiki_roots[0]}"
    test -f "$fractal_root/_node/NODE.md"
    test -f "$fractal_root/_scripts/start.sh"
    test -f "$fractal_root/core/schema.sql"
    test -f "$fractal_root/tui/app.tcss"
    test -f "$wiki_root/_assets/git/merge_index.sh"

    repo="$TMPDIR/fractal_smoke_repo"
    mkdir -p "$repo"
    ${git}/bin/git -C "$repo" init -b main
    ${git}/bin/git -C "$repo" config user.name "Fractal Smoke"
    ${git}/bin/git -C "$repo" config user.email "fractal-smoke@example.invalid"
    touch "$repo/.gitignore"
    ${git}/bin/git -C "$repo" add .gitignore
    ${git}/bin/git -C "$repo" commit -m baseline

    cd "$repo"
    run_fractal init --agent=codex
    test -f .fractal/main/config.json
    test -f .fractal/main/.db
    test -f wiki/_index.md
    grep -F '# >>> fractal >>>' .git/info/exclude

    run_fractal commit "initialize fractal" --init
    run_fractal node init smoke --max-iters=1 \
      > "$TMPDIR/node-init-stdout.txt" \
      2> "$TMPDIR/node-init-stderr.txt"
    cat "$TMPDIR/node-init-stdout.txt" "$TMPDIR/node-init-stderr.txt" \
      > "$TMPDIR/node-init-output.txt"
    if grep -F 'Could not download' "$TMPDIR/node-init-output.txt"; then
      cat "$TMPDIR/node-init-output.txt" >&2
      exit 1
    fi
    node_dir=.worktrees/main.smoke/.fractal/main.smoke
    test -f "$node_dir/config.json"
    test -w "$node_dir/NODE.md"
    test -w "$node_dir/steps/00-PREPARE.md"
    test -w "$node_dir/scripts/test.sh"
    test -w "$node_dir/.codex/config.toml"
    test -d "$node_dir/.codex/skills"
    test ! -L "$node_dir/.codex/skills"
    test -L "$node_dir/.codex/skills/fractal"
    test ! -e "$node_dir/.codex/skills/.system"
    run_wiki config --path="$node_dir/memory" > /dev/null
    symlink_target="$TMPDIR/wiki-symlink-target"
    touch "$symlink_target"
    chmod u-w "$symlink_target"
    ln -s "$symlink_target" \
      "$node_dir/memory/.wiki/obsidian/symlink-probe"
    run_wiki config --path="$node_dir/memory" > /dev/null
    test ! -w "$symlink_target"
    run_fractal node list > "$TMPDIR/node-list.txt"
    grep -F "main.smoke" "$TMPDIR/node-list.txt"

    mkdir -p "$out"
    cp "$TMPDIR/fractal-help.txt" "$TMPDIR/wiki-help.txt" \
      "$TMPDIR/node-init-output.txt" "$TMPDIR/node-list.txt" "$out/"
  ''
