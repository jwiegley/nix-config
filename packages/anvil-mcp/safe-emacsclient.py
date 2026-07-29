import getopt
import os
import stat
import sys

SHORT_OPTIONS = "nqueHVtca:F:w:s:f:d:T:"
LONG_OPTIONS = [
    "no-wait",
    "quiet",
    "suppress-output",
    "eval",
    "help",
    "version",
    "tty",
    "nw",
    "no-window-system",
    "create-frame",
    "reuse-frame",
    "alternate-editor=",
    "frame-parameters=",
    "socket-name=",
    "server-file=",
    "display=",
    "parent-id=",
    "timeout=",
    "tramp=",
]
LONG_NAMES = tuple(option.removesuffix("=") for option in LONG_OPTIONS)
SHORT_OPTION_NAMES = frozenset(SHORT_OPTIONS.replace(":", ""))
TERMINAL_OPTIONS = frozenset(("-H", "--help", "-V", "--version"))
EXIT_USAGE = 64
EXIT_RECURSION = 69


def delegate(real_client, arguments):
    os.execv(real_client, [real_client, *arguments])


def normalize_long_only(argument):
    """Normalize getopt_long_only's single-dash long-option syntax."""
    if not argument.startswith("-") or argument.startswith("--"):
        return argument
    candidate = argument[1:].split("=", 1)[0]
    if len(candidate) == 1 and candidate in SHORT_OPTION_NAMES:
        return argument
    if candidate in LONG_NAMES:
        return f"-{argument}"
    matches = [name for name in LONG_NAMES if name.startswith(candidate)]
    if len(matches) == 1:
        return f"-{argument}"
    return argument


def canonical_socket(target):
    """Resolve TARGET using the same local-socket rules as Emacsclient."""
    if "/" in target:
        return os.path.realpath(target)
    xdg_runtime = os.environ.get("XDG_RUNTIME_DIR")
    if xdg_runtime is not None:
        return os.path.realpath(f"{xdg_runtime}/emacs/{target}")
    temporary = os.environ.get("TMPDIR")
    if temporary is None and sys.platform == "darwin":
        try:
            temporary = os.confstr(65537)
        except (OSError, ValueError):
            temporary = None
    if temporary is None:
        temporary = "/tmp"
    return os.path.realpath(
        f"{temporary}/emacs{os.geteuid()}/{target}"
    )


def same_socket(candidate, root_socket):
    """Compare socket identity, returning None when root is unverifiable."""
    root = os.path.realpath(root_socket)
    if candidate == root:
        return True
    try:
        root_info = os.stat(root, follow_symlinks=False)
    except OSError:
        # Losing the authoritative path must not turn a same-root alias
        # into an apparently safe peer target.  The caller fails closed
        # for this indeterminate state.
        return None
    if not stat.S_ISSOCK(root_info.st_mode):
        return None
    try:
        candidate_info = os.stat(candidate, follow_symlinks=False)
    except OSError:
        return False
    if not stat.S_ISSOCK(candidate_info.st_mode):
        return False
    return (candidate_info.st_dev, candidate_info.st_ino) == (
        root_info.st_dev,
        root_info.st_ino,
    )


def terminal_precedes_parse_error(arguments):
    """Return whether real getopt exits for help/version before an error."""
    for end in range(1, len(arguments) + 1):
        try:
            options, _operands = getopt.gnu_getopt(
                arguments[:end], SHORT_OPTIONS, LONG_OPTIONS
            )
        except getopt.GetoptError as error:
            if end < len(arguments) and "requires argument" in str(error):
                continue
            return False
        if any(option in TERMINAL_OPTIONS for option, _value in options):
            return True
    return False


def main():
    if len(sys.argv) < 2:
        raise SystemExit(EXIT_USAGE)
    real_client = sys.argv[1]
    arguments = sys.argv[2:]
    root_socket = os.environ.get("ANVIL_EMACS_SOCKET")
    if not root_socket:
        delegate(real_client, arguments)

    # Emacsclient uses getopt_long_only: in addition to ordinary short
    # clusters and double-dash long options it accepts exact or unique
    # long names after one dash (`-socket-name', `-so', and `-nw').
    parse_arguments = [normalize_long_only(arg) for arg in arguments]
    try:
        options, _operands = getopt.gnu_getopt(
            parse_arguments,
            SHORT_OPTIONS,
            LONG_OPTIONS,
        )
    except getopt.GetoptError:
        if terminal_precedes_parse_error(parse_arguments):
            delegate(real_client, arguments)
        print(
            "anvil-mcp: refusing an emacsclient invocation whose options "
            "cannot be checked safely",
            file=sys.stderr,
        )
        raise SystemExit(EXIT_USAGE)

    socket_values = []
    server_file_values = []
    for option, value in options:
        if option in ("-s", "--socket-name"):
            socket_values.append(value)
        elif option in ("-f", "--server-file"):
            server_file_values.append(value)
        elif option in TERMINAL_OPTIONS:
            delegate(real_client, arguments)

    socket_name = (
        socket_values[-1]
        if socket_values
        else os.environ.get("EMACS_SOCKET_NAME")
    )
    if socket_name is not None:
        effective_socket = canonical_socket(socket_name)
    else:
        server_file = (
            server_file_values[-1]
            if server_file_values
            else os.environ.get("EMACS_SERVER_FILE")
        )
        if server_file is not None:
            delegate(real_client, arguments)
        # A guarded child with no explicit selector is attempting the
        # authoritative active root, regardless of its direnv runtime.
        effective_socket = os.path.realpath(root_socket)

    same_root = same_socket(effective_socket, root_socket)
    if same_root is not False:
        print(
            "anvil-mcp: refusing recursive or unverifiable emacsclient "
            "call from the active Anvil root",
            file=sys.stderr,
        )
        raise SystemExit(EXIT_RECURSION)
    delegate(real_client, arguments)


if __name__ == "__main__":
    main()
