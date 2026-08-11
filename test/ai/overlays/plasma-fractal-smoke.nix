{
  coreutils,
  git,
  gnugrep,
  plasma-fractal,
  plasma-wiki,
  python3,
  runCommand,
}:

let
  testPython = python3.withPackages (ps: [ ps.typer ]);
in
runCommand "plasma-fractal-smoke"
  {
    nativeBuildInputs = [
      coreutils
      gnugrep
      testPython
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

    test "$(run_fractal --version)" = "${plasma-fractal.version}"
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
    wiki_site_packages="''${wiki_root%/wiki}"
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
    chmod 0444 "$symlink_target"
    symlink_target_mode="$(${coreutils}/bin/stat -c '%a' "$symlink_target")"
    ln -s "$symlink_target" \
      "$node_dir/memory/.wiki/obsidian/symlink-probe"
    writable_0200="$node_dir/memory/.wiki/obsidian/writable-0200"
    touch "$writable_0200"
    chmod 0200 "$writable_0200"
    metadata_source_dir="$node_dir/memory/.wiki/obsidian/plugins/metadata-contract"
    metadata_source="$metadata_source_dir/data"
    mkdir -p "$metadata_source_dir"
    echo metadata-contract > "$metadata_source"
    chmod 0440 "$metadata_source"
    metadata_times="$TMPDIR/metadata-times"
    ${testPython}/bin/python3 - "$metadata_source" "$metadata_times" <<'PY'
    import os
    import pathlib
    import sys

    source = pathlib.Path(sys.argv[1])
    expected = pathlib.Path(sys.argv[2])
    os_times = (946684800_123456789, 946684800_987654321)
    source.touch()
    source.chmod(0o440)
    os.utime(source, ns=os_times)
    info = source.stat()
    expected.write_text(f'{info.st_atime_ns}\n{info.st_mtime_ns}\n')
    PY
    run_wiki config --path="$node_dir/memory" > /dev/null
    test -L "$node_dir/memory/.wiki/obsidian/symlink-probe"
    test "$(${coreutils}/bin/stat -c '%a' "$symlink_target")" \
      = "$symlink_target_mode"
    test ! -w "$symlink_target"
    test "$(${coreutils}/bin/stat -c '%a' "$writable_0200")" = 200
    metadata_target="$node_dir/memory/.obsidian/plugins/metadata-contract/data"
    test "$(${coreutils}/bin/stat -c '%a' "$metadata_target")" = 640

    plugins_root="$node_dir/memory/.obsidian/plugins"
    external_plugins="$TMPDIR/external-plugins"
    external_plugin="$external_plugins/obsidian-front-matter-title-plugin"
    external_plugin_file="$external_plugin/data.json"
    mkdir -p "$external_plugin"
    echo ancestor-sentinel > "$external_plugin_file"
    chmod 0555 "$external_plugins" "$external_plugin"
    chmod 0444 "$external_plugin_file"
    ancestor_modes="$(${coreutils}/bin/stat -c '%a' \
      "$external_plugins" "$external_plugin" "$external_plugin_file")"
    ancestor_hash="$(${coreutils}/bin/sha256sum "$external_plugin_file")"
    mv "$plugins_root" "$plugins_root.real"
    ln -s "$external_plugins" "$plugins_root"
    if run_wiki config --path="$node_dir/memory" \
      > "$TMPDIR/wiki-symlink-ancestor-output.txt" 2>&1; then
      echo "wiki accepted a symlinked Obsidian destination ancestor" >&2
      exit 1
    fi
    grep -iF symlink "$TMPDIR/wiki-symlink-ancestor-output.txt"
    test "$(${coreutils}/bin/stat -c '%a' \
      "$external_plugins" "$external_plugin" "$external_plugin_file")" \
      = "$ancestor_modes"
    test "$(${coreutils}/bin/sha256sum "$external_plugin_file")" \
      = "$ancestor_hash"
    unlink "$plugins_root"
    mv "$plugins_root.real" "$plugins_root"

    PYTHONPATH="$wiki_site_packages" ${testPython}/bin/python3 - \
      "$TMPDIR" "$metadata_target" "$metadata_times" <<'PY'
    import errno
    import os
    import pathlib
    import stat
    import sys

    from wiki.core import _obsidian
    from wiki.core.wiki import Wiki

    assert _obsidian._RootedDirectory._METADATA_CONTRACT == (
        'regular-file-contents',
        'permission-bits-plus-owner-write',
        'nanosecond-atime-mtime',
        'descriptor-addressable-xattrs-and-flags',
        'metadata-without-public-fd-api-excluded',
    )

    base = pathlib.Path(sys.argv[1]) / 'wiki-copy-swap'
    metadata_target = pathlib.Path(sys.argv[2])
    expected_times = tuple(
        int(value) for value in pathlib.Path(sys.argv[3]).read_text().splitlines()
    )
    metadata_info = metadata_target.stat()
    assert (metadata_info.st_atime_ns, metadata_info.st_mtime_ns) == expected_times
    root = base / 'root'
    source = base / 'source'
    target = root / '.obsidian' / 'plugins' / 'swap-probe'
    detached = base / 'detached-target'
    external = base / 'external-target'
    external_file = external / 'payload'
    source.mkdir(parents=True)
    target.mkdir(parents=True)
    external.mkdir(parents=True)
    (source / 'payload').write_text('source\n')
    external_file.write_text('external-sentinel\n')
    external.chmod(0o555)
    external_file.chmod(0o444)

    capability_root = base / 'linux-capability'
    capability_root.mkdir()
    unreadable = capability_root / 'unreadable'
    unreadable.write_bytes(b'unreadable\n')
    unreadable.chmod(0o000)
    try:
        with _obsidian._RootedDirectory.open(capability_root) as capability:
            capability.make_writable()
    except NotImplementedError:
        assert stat.S_IMODE(unreadable.stat().st_mode) == 0o000
    else:
        assert stat.S_IMODE(unreadable.stat().st_mode) == 0o200

    init_root = base / 'init-root'
    init_external = base / 'init-external'
    init_root.mkdir()
    init_external.mkdir()
    (init_external / 'sentinel').write_bytes(b'unchanged\n')
    (init_root / '.wiki').symlink_to(init_external, target_is_directory=True)
    init_before = sorted(
        (entry.name, entry.read_bytes()) for entry in init_external.iterdir()
    )
    try:
        Wiki(init_root).init()
    except RuntimeError as error:
        assert 'symlink' in str(error).lower()
    else:
        raise AssertionError('init accepted a symlinked .wiki directory')
    init_after = sorted(
        (entry.name, entry.read_bytes()) for entry in init_external.iterdir()
    )
    assert init_after == init_before

    def numeric_modes(*paths: pathlib.Path) -> tuple[int, ...]:
        return tuple(stat.S_IMODE(path.lstat().st_mode) for path in paths)

    external_modes = numeric_modes(external, external_file)
    external_contents = external_file.read_bytes()
    real_copy_contents = _obsidian._RootedDirectory._copy_contents
    swapped = False

    def swap_after_open(source_fd, destination_fd):
        global swapped
        if not swapped:
            target.rename(detached)
            target.symlink_to(external, target_is_directory=True)
            swapped = True
        return real_copy_contents(source_fd, destination_fd)

    _obsidian._RootedDirectory._copy_contents = staticmethod(swap_after_open)
    try:
        try:
            with _obsidian._RootedDirectory.open(root) as rooted:
                with _obsidian._RootedDirectory.open(source) as source_tree:
                    with rooted.directory(
                        pathlib.PurePath('.obsidian') / 'plugins' / 'swap-probe'
                    ) as destination_tree:
                        destination_tree.copytree_from(source_tree)
        except RuntimeError as error:
            if 'changed during operation' not in str(error):
                raise
        else:
            raise AssertionError('copy accepted a swapped destination')
    finally:
        _obsidian._RootedDirectory._copy_contents = staticmethod(
            real_copy_contents
        )

    assert swapped
    assert numeric_modes(external, external_file) == external_modes
    assert external_file.read_bytes() == external_contents

    hardlink_root = base / 'hardlink-root'
    hardlink_root.mkdir()
    hardlink_external = base / 'hardlink-external'
    hardlink_external.write_bytes(b'hardlink-sentinel\n')
    hardlink_external.chmod(0o444)
    (hardlink_root / 'alias').hardlink_to(hardlink_external)
    hardlink_mode = numeric_modes(hardlink_external)
    hardlink_contents = hardlink_external.read_bytes()
    with _obsidian._RootedDirectory.open(hardlink_root) as hardlink_tree:
        hardlink_tree.make_writable()
    assert numeric_modes(hardlink_external) == hardlink_mode
    assert hardlink_external.read_bytes() == hardlink_contents
    alias_info = (hardlink_root / 'alias').stat()
    external_hardlink_info = hardlink_external.stat()
    assert stat.S_IMODE(alias_info.st_mode) == 0o644
    assert (alias_info.st_dev, alias_info.st_ino) != (
        external_hardlink_info.st_dev,
        external_hardlink_info.st_ino,
    )

    fd_leak_root = base / 'fd-leak-root'
    fd_leak_root.mkdir()
    (fd_leak_root / 'payload').write_bytes(b'fd-leak\n')
    (fd_leak_root / 'payload').chmod(0o400)
    real_fstat = os.fstat
    opened_fds = []

    def fail_regular_fstat(fd):
        info = real_fstat(fd)
        if stat.S_ISREG(info.st_mode) and not opened_fds:
            opened_fds.append(fd)
            raise OSError(errno.EIO, 'injected fstat failure')
        return info

    _obsidian.os.fstat = fail_regular_fstat
    try:
        try:
            with _obsidian._RootedDirectory.open(fd_leak_root) as leak_tree:
                leak_tree.make_writable()
        except OSError as error:
            assert error.errno == errno.EIO
        else:
            raise AssertionError('injected fstat failure was not observed')
    finally:
        _obsidian.os.fstat = real_fstat
    assert len(opened_fds) == 1
    try:
        os.fstat(opened_fds[0])
    except OSError as error:
        assert error.errno == errno.EBADF
    else:
        raise AssertionError('fstat validation leaked its file descriptor')

    copy_source = base / 'hardlink-copy-source'
    copy_target = base / 'hardlink-copy-target'
    copy_source.mkdir()
    copy_target.mkdir()
    source_payload = copy_source / 'payload'
    source_payload.write_bytes(b'replacement\n')
    source_payload.chmod(0o1750)
    assert stat.S_IMODE(source_payload.stat().st_mode) == 0o1750
    copy_external = base / 'hardlink-copy-external'
    copy_external.write_bytes(b'external-copy-sentinel\n')
    copy_external.chmod(0o440)
    (copy_target / 'payload').hardlink_to(copy_external)
    copy_external_info = copy_external.stat()
    with _obsidian._RootedDirectory.open(copy_source) as source_tree:
        with _obsidian._RootedDirectory.open(copy_target) as target_tree:
            target_tree._copy_file_from(source_tree, 'payload')
    copied_info = (copy_target / 'payload').stat()
    assert (copy_external.stat().st_dev, copy_external.stat().st_ino) == (
        copy_external_info.st_dev,
        copy_external_info.st_ino,
    )
    assert copy_external.read_bytes() == b'external-copy-sentinel\n'
    assert (copied_info.st_dev, copied_info.st_ino) != (
        copy_external_info.st_dev,
        copy_external_info.st_ino,
    )
    assert (copy_target / 'payload').read_bytes() == b'replacement\n'
    assert stat.S_IMODE(copied_info.st_mode) == 0o750

    umask_root = base / 'umask-root'
    umask_root.mkdir()
    previous_umask = os.umask(0o027)
    try:
        with _obsidian._RootedDirectory.open(umask_root) as umask_tree:
            umask_tree.write_text('fresh', 'fresh\n')
    finally:
        os.umask(previous_umask)
    assert stat.S_IMODE((umask_root / 'fresh').stat().st_mode) == 0o640

    stage_root = base / 'stage-root'
    stage_root.mkdir()
    (stage_root / 'destination').write_bytes(b'original\n')
    with _obsidian._RootedDirectory.open(stage_root) as stage_directory:
        temporary = stage_directory.private_temp()
        try:
            assert stat.S_IMODE(os.fstat(temporary._stage_fd).st_mode) == 0o700
            temporary.write_bytes(b'expected\n')
            original_name = f'{temporary._FILENAME}.original'
            os.rename(
                temporary._FILENAME,
                original_name,
                src_dir_fd=temporary._stage_fd,
                dst_dir_fd=temporary._stage_fd,
            )
            replacement_fd = os.open(
                temporary._FILENAME,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
                dir_fd=temporary._stage_fd,
            )
            try:
                os.write(replacement_fd, b'attacker\n')
            finally:
                os.close(replacement_fd)
            try:
                stage_directory.install_temp(temporary, 'destination')
            except RuntimeError as error:
                if 'Staged file changed' not in str(error):
                    raise
            else:
                raise AssertionError('install accepted a replaced staged file')
            assert stage_directory.read_bytes('destination') == b'original\n'
            os.unlink(temporary._FILENAME, dir_fd=temporary._stage_fd)
            os.rename(
                original_name,
                temporary._FILENAME,
                src_dir_fd=temporary._stage_fd,
                dst_dir_fd=temporary._stage_fd,
            )
        finally:
            temporary.close()

        broken = stage_directory.private_temp()
        broken_stage_fd = broken._stage_fd
        broken_file_fd = broken._fd
        os.unlink(broken._FILENAME, dir_fd=broken_stage_fd)
        os.mkdir(broken._FILENAME, mode=0o700, dir_fd=broken_stage_fd)
        try:
            broken.close()
        except OSError:
            pass
        else:
            raise AssertionError('broken stage cleanup unexpectedly succeeded')
        for closed_fd in (broken_file_fd, broken_stage_fd):
            try:
                os.fstat(closed_fd)
            except OSError as error:
                assert error.errno == errno.EBADF
            else:
                raise AssertionError('stage cleanup leaked a descriptor')
        with stage_directory.directory(broken._stage_name) as broken_directory:
            os.rmdir(broken._FILENAME, dir_fd=broken_directory.fd)
        os.rmdir(broken._stage_name, dir_fd=stage_directory.fd)

    transaction_root = base / 'transaction-root'
    transaction_root.mkdir()
    (transaction_root / 'main.js').write_bytes(b'old-main\n')
    (transaction_root / 'manifest.json').write_bytes(b'old-manifest\n')
    (transaction_root / 'main.js').chmod(0o440)
    (transaction_root / 'manifest.json').chmod(0o640)
    old_assets = {
        name: (
            (transaction_root / name).read_bytes(),
            stat.S_IMODE((transaction_root / name).stat().st_mode),
        )
        for name in ('main.js', 'manifest.json')
    }
    with _obsidian._RootedDirectory.open(transaction_root) as transaction:
        staged = []
        for name, contents in (
            ('main.js', b'new-main\n'),
            ('manifest.json', b'new-manifest\n'),
        ):
            temporary = transaction.private_temp()
            temporary.write_bytes(contents)
            staged.append((temporary, name))
        real_rename = os.rename
        failed_commit = False

        def fail_second_asset(source, destination, *args, **kwargs):
            global failed_commit
            if destination == 'manifest.json' and not failed_commit:
                failed_commit = True
                real_rename(source, destination, *args, **kwargs)
                raise OSError(errno.EIO, 'injected second-asset failure')
            return real_rename(source, destination, *args, **kwargs)

        _obsidian.os.rename = fail_second_asset
        try:
            try:
                transaction.install_many(staged)
            except OSError as error:
                assert error.errno == errno.EIO
            else:
                raise AssertionError('second-asset commit failure was ignored')
        finally:
            _obsidian.os.rename = real_rename
            for temporary, _ in staged:
                temporary.close()
        assert failed_commit
        assert {
            name: (
                transaction.read_bytes(name),
                stat.S_IMODE(
                    os.stat(
                        name,
                        dir_fd=transaction.fd,
                        follow_symlinks=False,
                    ).st_mode
                ),
            )
            for name in ('main.js', 'manifest.json')
        } == old_assets
        assert not any(
            name.startswith('.wiki-stage-') for name, _ in transaction.entries()
        )

        staged = []
        for name, contents in (
            ('main.js', b'new-main\n'),
            ('manifest.json', b'new-manifest\n'),
        ):
            temporary = transaction.private_temp()
            temporary.write_bytes(contents)
            staged.append((temporary, name))
        try:
            transaction.install_many(staged)
        finally:
            for temporary, _ in staged:
                temporary.close()
        assert transaction.read_bytes('main.js') == b'new-main\n'
        assert transaction.read_bytes('manifest.json') == b'new-manifest\n'
        assert not any(
            name.startswith('.wiki-stage-') for name, _ in transaction.entries()
        )

    mode_race_root = base / 'mode-race-root'
    mode_race_root.mkdir()
    (mode_race_root / 'main.js').write_bytes(b'pre-open-a\n')
    (mode_race_root / 'main.js').chmod(0o777)
    (mode_race_root / 'manifest.json').write_bytes(b'old-manifest\n')
    mode_race_replacement = base / 'mode-race-replacement'
    mode_race_replacement.write_bytes(b'pre-open-b\n')
    mode_race_replacement.chmod(0o600)
    assert stat.S_IMODE((mode_race_root / 'main.js').stat().st_mode) == 0o777
    with _obsidian._RootedDirectory.open(mode_race_root) as mode_transaction:
        staged = []
        for name, contents in (
            ('main.js', b'new-main\n'),
            ('manifest.json', b'new-manifest\n'),
        ):
            temporary = mode_transaction.private_temp()
            temporary.write_bytes(contents)
            staged.append((temporary, name))
        real_open_regular = mode_transaction._open_regular
        real_rename = os.rename
        opened_replacement = False
        failed_commit = False

        def swap_before_open(name, flags, mode=0o666):
            global opened_replacement
            if name == 'main.js' and not opened_replacement:
                os.replace(mode_race_replacement, mode_race_root / name)
                opened_replacement = True
            return real_open_regular(name, flags, mode)

        def fail_mode_race_commit(source, destination, *args, **kwargs):
            global failed_commit
            if destination == 'manifest.json' and not failed_commit:
                failed_commit = True
                real_rename(source, destination, *args, **kwargs)
                raise OSError(errno.EIO, 'injected mode-race commit failure')
            return real_rename(source, destination, *args, **kwargs)

        mode_transaction._open_regular = swap_before_open
        _obsidian.os.rename = fail_mode_race_commit
        try:
            try:
                mode_transaction.install_many(staged)
            except OSError as error:
                assert error.errno == errno.EIO
            else:
                raise AssertionError('mode-race commit failure was ignored')
        finally:
            mode_transaction._open_regular = real_open_regular
            _obsidian.os.rename = real_rename
            for temporary, _ in staged:
                temporary.close()
        assert opened_replacement
        assert failed_commit
        assert mode_transaction.read_bytes('main.js') == b'pre-open-b\n'
        main_info = os.stat(
            'main.js',
            dir_fd=mode_transaction.fd,
            follow_symlinks=False,
        )
        assert stat.S_IMODE(main_info.st_mode) == 0o600
        assert mode_transaction.read_bytes('manifest.json') == b'old-manifest\n'
        assert not any(
            name.startswith('.wiki-stage-')
            for name, _ in mode_transaction.entries()
        )

    if all(hasattr(os, name) for name in ('listxattr', 'getxattr', 'setxattr')):
        xattr_source = base / 'xattr-source'
        xattr_target = base / 'xattr-target'
        xattr_source.mkdir()
        xattr_target.mkdir()
        (xattr_source / 'payload').write_bytes(b'xattr\n')
        source_fd = os.open(xattr_source / 'payload', os.O_RDWR | os.O_NOFOLLOW)
        try:
            try:
                os.setxattr(source_fd, 'user.wiki-test', b'preserved')
            except (TypeError, NotImplementedError):
                xattrs_supported = False
            except OSError as error:
                unsupported = {
                    getattr(errno, name, None)
                    for name in (
                        'EACCES',
                        'EINVAL',
                        'ENOSYS',
                        'ENOTSUP',
                        'EOPNOTSUPP',
                        'EPERM',
                    )
                }
                if error.errno not in unsupported:
                    raise
                xattrs_supported = False
            else:
                xattrs_supported = True
        finally:
            os.close(source_fd)
        if xattrs_supported:
            with _obsidian._RootedDirectory.open(xattr_source) as source_tree:
                with _obsidian._RootedDirectory.open(xattr_target) as target_tree:
                    target_tree.copytree_from(source_tree)
            target_fd = os.open(
                xattr_target / 'payload',
                os.O_RDONLY | os.O_NOFOLLOW,
            )
            try:
                assert os.getxattr(target_fd, 'user.wiki-test') == b'preserved'
            finally:
                os.close(target_fd)
    PY

    obsidian_root="$node_dir/memory/.wiki/obsidian"
    external_obsidian="$TMPDIR/external-obsidian"
    external_dir="$external_obsidian/mode-probe"
    external_probe="$external_dir/leaf"
    mkdir -p "$external_dir"
    touch "$external_probe"
    chmod 0555 "$external_obsidian" "$external_dir"
    chmod 0444 "$external_probe"
    external_modes="$(${coreutils}/bin/stat -c '%a' \
      "$external_obsidian" "$external_dir" "$external_probe")"
    mv "$obsidian_root" "$obsidian_root.real"
    ln -s "$external_obsidian" "$obsidian_root"
    if run_wiki config --path="$node_dir/memory" \
      > "$TMPDIR/wiki-symlink-root-output.txt" 2>&1; then
      echo "wiki accepted a symlink Obsidian root" >&2
      exit 1
    fi
    grep -iF symlink \
      "$TMPDIR/wiki-symlink-root-output.txt"
    test "$(${coreutils}/bin/stat -c '%a' \
      "$external_obsidian" "$external_dir" "$external_probe")" \
      = "$external_modes"
    test -L "$obsidian_root"
    unlink "$obsidian_root"
    mv "$obsidian_root.real" "$obsidian_root"
    run_fractal node list > "$TMPDIR/node-list.txt"
    grep -F "main.smoke" "$TMPDIR/node-list.txt"

    mkdir -p "$out"
    cp "$TMPDIR/fractal-help.txt" "$TMPDIR/wiki-help.txt" \
      "$TMPDIR/node-init-output.txt" "$TMPDIR/node-list.txt" "$out/"
  ''
