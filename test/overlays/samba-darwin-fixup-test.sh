#!/usr/bin/env bash

set -eu
# Start with pipefail off so the sourced production fragment must enable it.
set +o pipefail

: "${FIXUP_SCRIPT:?FIXUP_SCRIPT is required}"

test_root=$(mktemp -d "${TMPDIR%/}/samba-darwin-fixup-test.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT
fake_bin=$test_root/fake-bin
export out="$test_root/out with space"
export NIX_BUILD_TOP="$test_root/build with space"
export SAMBA_TEST_INSTALL_LOG=$test_root/install.log
export SAMBA_TEST_OTOOL_LOG=$test_root/otool.log
export SAMBA_TEST_FIXED=$test_root/fixed
export SAMBA_TEST_SUBJECT="$out/bin/subject"

mkdir -p "$fake_bin" "$out/bin" "$out/lib" "$NIX_BUILD_TOP/lib"
export PATH="$fake_bin:$PATH"

cat >"$fake_bin/otool" <<'EOF'
#!/usr/bin/env bash
set -eu

printf '%s\n' "$*" >>"$SAMBA_TEST_OTOOL_LOG"
operation=$1
bin=$2
mode=${SAMBA_TEST_MODE:-happy}

if [[ $operation == -L && $mode == load-fail ]]; then
    exit 9
fi
if [[ $operation == -L && $mode == invalid-load ]]; then
	printf '%s: is not an object file\n' "$bin"
	exit 0
fi
if [[ $operation == -l && $mode == id-fail ]]; then
    exit 9
fi

printf '%s:\n' "$bin"
if [[ $operation == -L && $mode == invalid-line ]]; then
	printf '\tmalformed load-command line\n'
elif [[ $operation == -L && $bin == "$SAMBA_TEST_SUBJECT" ]]; then
    if [[ $mode == residual || ! -e $SAMBA_TEST_FIXED ]]; then
        printf '\t%s/lib/libone.dylib (compatibility version 1.0.0, current version 1.0.0)\n' \
            "$NIX_BUILD_TOP"
        printf '\t%s/lib/libtwo.dylib (compatibility version 1.0.0, current version 1.0.0)\n' \
            "$NIX_BUILD_TOP"
    else
        printf '\t%s/lib/libone.dylib (compatibility version 1.0.0, current version 1.0.0)\n' \
            "$out"
        printf '\t%s/lib/libtwo.dylib (compatibility version 1.0.0, current version 1.0.0)\n' \
            "$out"
    fi
elif [[ $operation == -l && $bin == "$SAMBA_TEST_SUBJECT" ]]; then
    printf 'Load command 0\n'
    printf '          cmd LC_ID_DYLIB\n'
fi
EOF
chmod +x "$fake_bin/otool"

cat >"$fake_bin/install_name_tool" <<'EOF'
#!/usr/bin/env bash
set -eu

[[ ${SAMBA_TEST_MODE:-happy} != install-fail ]] || exit 9
printf 'CALL\n' >>"$SAMBA_TEST_INSTALL_LOG"
printf '%s\n' "$@" >>"$SAMBA_TEST_INSTALL_LOG"
printf 'END\n' >>"$SAMBA_TEST_INSTALL_LOG"
touch "$SAMBA_TEST_FIXED"
EOF
chmod +x "$fake_bin/install_name_tool"

# shellcheck source=/dev/null
source "$FIXUP_SCRIPT"

write_macho() {
    printf '\xcf\xfa\xed\xfe\000fixture' >"$1"
}

reset_fixture() {
    rm -rf "$out" "$NIX_BUILD_TOP"
    rm -f "$SAMBA_TEST_FIXED" "$SAMBA_TEST_INSTALL_LOG" "$SAMBA_TEST_OTOOL_LOG"
    mkdir -p "$out/bin" "$out/lib" "$NIX_BUILD_TOP/lib"
    write_macho "$SAMBA_TEST_SUBJECT"
    write_macho "$out/lib/libone.dylib"
    write_macho "$out/lib/libtwo.dylib"
    printf 'not an object\n' >"$out/bin/readme"
    samba_libs=("$out/lib")
    SAMBA_TEST_MODE=happy
    export SAMBA_TEST_MODE
}

expect_failure() {
    local label=$1
    shift
    if "$@" >"$test_root/$label.stdout" 2>"$test_root/$label.stderr"; then
        printf 'expected failure: %s\n' "$label" >&2
        exit 1
    fi
}

reset_fixture
samba_fix_macho_tree
samba_verify_macho_tree
mapfile -t install_log <"$SAMBA_TEST_INSTALL_LOG"
expected_install_log=(
    CALL
    -id
    "$SAMBA_TEST_SUBJECT"
    -change
    "$NIX_BUILD_TOP/lib/libone.dylib"
    "$out/lib/libone.dylib"
    -change
    "$NIX_BUILD_TOP/lib/libtwo.dylib"
    "$out/lib/libtwo.dylib"
    "$SAMBA_TEST_SUBJECT"
    END
)
[[ ${#install_log[@]} -eq ${#expected_install_log[@]} ]]
for index in "${!expected_install_log[@]}"; do
    [[ ${install_log[$index]} == "${expected_install_log[$index]}" ]]
done

reset_fixture
: >"$SAMBA_TEST_OTOOL_LOG"
samba_fix_macho "$out/bin/readme"
[[ ! -s $SAMBA_TEST_OTOOL_LOG ]]

reset_fixture
cat >"$fake_bin/od" <<'EOF'
#!/usr/bin/env bash
exit 9
EOF
chmod +x "$fake_bin/od"
expect_failure classifier samba_fix_macho "$SAMBA_TEST_SUBJECT"
rm "$fake_bin/od"

reset_fixture
SAMBA_TEST_MODE=load-fail
expect_failure load samba_fix_macho "$SAMBA_TEST_SUBJECT"

reset_fixture
SAMBA_TEST_MODE=invalid-load
expect_failure invalid-load samba_fix_macho "$SAMBA_TEST_SUBJECT"

reset_fixture
SAMBA_TEST_MODE=invalid-line
expect_failure invalid-line samba_fix_macho "$SAMBA_TEST_SUBJECT"

reset_fixture
SAMBA_TEST_MODE=id-fail
expect_failure id samba_fix_macho "$SAMBA_TEST_SUBJECT"

reset_fixture
samba_libs=("$out/empty")
mkdir -p "${samba_libs[0]}"
expect_failure replacement samba_fix_macho "$SAMBA_TEST_SUBJECT"

reset_fixture
SAMBA_TEST_MODE=install-fail
expect_failure install samba_fix_macho "$SAMBA_TEST_SUBJECT"

reset_fixture
SAMBA_TEST_MODE=load-fail
expect_failure residual-load samba_verify_macho "$SAMBA_TEST_SUBJECT"

reset_fixture
SAMBA_TEST_MODE=residual
expect_failure residual-reference samba_verify_macho "$SAMBA_TEST_SUBJECT"

reset_fixture
cat >"$fake_bin/find" <<'EOF'
#!/usr/bin/env bash
set -eu

case " $* " in
*' -regex '*)
	printf '%s\0' "$out/lib"
	exit 9
	;;
*) exit 0 ;;
esac
EOF
chmod +x "$fake_bin/find"
expect_failure library-enumeration samba_fix_macho_tree
rm "$fake_bin/find"

reset_fixture
cat >"$fake_bin/find" <<'EOF'
#!/usr/bin/env bash
set -eu

case " $* " in
*' -regex '*) printf '%s\0' "$out/lib" ;;
*)
	printf '%s\0' "$SAMBA_TEST_SUBJECT"
	exit 9
	;;
esac
EOF
chmod +x "$fake_bin/find"
expect_failure mutation-traversal samba_fix_macho_tree
rm "$fake_bin/find"

reset_fixture
touch "$SAMBA_TEST_FIXED"
cat >"$fake_bin/find" <<'EOF'
#!/usr/bin/env bash
set -eu

printf '%s\0' "$SAMBA_TEST_SUBJECT"
exit 9
EOF
chmod +x "$fake_bin/find"
expect_failure residual-traversal samba_verify_macho_tree
rm "$fake_bin/find"

reset_fixture
SAMBA_TEST_MODE=load-fail
expect_failure mutation-leaf samba_fix_macho_tree

reset_fixture
SAMBA_TEST_MODE=load-fail
expect_failure residual-leaf samba_verify_macho_tree

printf 'samba-darwin-fixup: all cases passed\n'
