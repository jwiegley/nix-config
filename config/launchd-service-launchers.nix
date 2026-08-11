{
  lib,
  pkgs,
}:

let
  isCanonicalAbsolute =
    path:
    builtins.isString path
    && (
      path == "/"
      || (
        lib.hasPrefix "/" path
        && !lib.hasSuffix "/" path
        && lib.all (component: component != "" && component != "." && component != "..") (
          lib.tail (lib.splitString "/" path)
        )
      )
    );
  isDescendant = root: path: root == "/" && path != "/" || lib.hasPrefix "${root}/" path;

  closeUnrelatedDescriptorsSource = ''
    static int list_descriptors(
        struct proc_fdinfo *descriptors, size_t capacity
    ) {
        errno = 0;
        int bytes = proc_pidinfo(
            getpid(), PROC_PIDLISTFDS, 0,
            descriptors, (int)(capacity * sizeof(descriptors[0]))
        );
        if (
            bytes < 0
            || (bytes == 0 && errno != 0)
            || bytes % (int)sizeof(descriptors[0]) != 0
        ) {
            return -1;
        }
        return bytes;
    }

    static int close_unrelated_descriptors(int keep) {
        struct proc_fdinfo descriptors[16];
        for (;;) {
            int bytes = list_descriptors(
                descriptors, sizeof(descriptors) / sizeof(descriptors[0])
            );
            if (bytes < 0) return -1;
            int count = bytes / (int)sizeof(descriptors[0]);
            int closed = 0;
            for (int index = 0; index < count; ++index) {
                int descriptor = descriptors[index].proc_fd;
                if (descriptor <= STDERR_FILENO || descriptor == keep) continue;
                if (close(descriptor) < 0 && errno != EBADF) return -1;
                closed = 1;
            }
            if (bytes < (int)sizeof(descriptors)) return 0;
            if (!closed) {
                errno = EMFILE;
                return -1;
            }
        }
    }
  '';

  descriptorSanitizerSource = pkgs.writeText "launchd-descriptor-sanitizer.c" ''
    #define _DARWIN_C_SOURCE 1
    #include <errno.h>
    #include <libproc.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <sys/proc_info.h>
    #include <sys/types.h>
    #include <unistd.h>

    ${closeUnrelatedDescriptorsSource}

    int main(int argc, char **argv) {
        if (argc < 3 || (strcmp(argv[1], "-1") != 0 && strcmp(argv[1], "3") != 0)) {
            fputs("launchd-fd-exec: invalid invocation\n", stderr);
            return EXIT_FAILURE;
        }
        int keep = strcmp(argv[1], "3") == 0 ? 3 : -1;
        if (argv[2][0] != '/' || close_unrelated_descriptors(keep) != 0) {
            fputs("launchd-fd-exec: descriptor sanitization failed\n", stderr);
            return EXIT_FAILURE;
        }
        char *const sanitized_environment[] = { NULL };
        execve(argv[2], &argv[2], sanitized_environment);
        fprintf(stderr, "launchd-fd-exec: exec: %s\n", strerror(errno));
        return EXIT_FAILURE;
    }
  '';
  descriptorSanitizer = pkgs.runCommandCC "launchd-descriptor-sanitizer" { } ''
    mkdir -p "$out/bin"
    "$CC" -std=c11 -Wall -Wextra -Werror \
      ${descriptorSanitizerSource} \
      -o "$out/bin/launchd-fd-exec"
  '';

  mssqlPathValidator = pkgs.writeText "validate-mssql-paths.py" ''
    import ctypes
    import errno
    import os
    import stat
    import sys

    libc = ctypes.CDLL(None, use_errno=True)
    libc.acl_get_fd_np.argtypes = [ctypes.c_int, ctypes.c_int]
    libc.acl_get_fd_np.restype = ctypes.c_void_p
    libc.acl_free.argtypes = [ctypes.c_void_p]
    libc.acl_free.restype = ctypes.c_int
    ACL_TYPE_EXTENDED = 0x00000100

    def fail(message):
        sys.stderr.write(f"mssql-server: {message}\n")
        raise SystemExit(1)

    def components(path):
        if not path.startswith("/") or (path != "/" and path.endswith("/")):
            fail("managed paths must be canonical absolute paths")
        result = path.split("/")[1:]
        if path == "/":
            return []
        if any(component in ("", ".", "..") for component in result):
            fail("managed paths must not contain empty, dot, or dot-dot components")
        if os.path.normpath(path) != path:
            fail("managed paths must be normalized")
        return result

    def relative_components(root, path):
        root_components = components(root)
        path_components = components(path)
        if path_components[:len(root_components)] != root_components or path_components == root_components:
            fail("managed path is outside its trusted root")
        return path_components[len(root_components):]

    def open_directory(parent, component, label):
        try:
            return os.open(
                component,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                dir_fd=parent,
            )
        except OSError:
            fail(f"{label} must be a real directory")

    def open_trust_root(path):
        descriptor = os.open(
            "/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
        )
        for component in components(path):
            next_descriptor = open_directory(descriptor, component, "trusted root")
            os.close(descriptor)
            descriptor = next_descriptor
        return descriptor

    def require_no_acl(descriptor, label):
        ctypes.set_errno(0)
        acl = libc.acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED)
        if acl:
            if libc.acl_free(acl) != 0:
                fail(f"{label} ACL metadata could not be released")
            fail(f"{label} must not have ACL entries")
        if ctypes.get_errno() != errno.ENOENT:
            fail(f"{label} ACL metadata is unavailable")

    def validate_directory(descriptor, owner, label, exact_mode=None):
        metadata = os.fstat(descriptor)
        mode = stat.S_IMODE(metadata.st_mode)
        if not stat.S_ISDIR(metadata.st_mode):
            fail(f"{label} must be a directory")
        if metadata.st_uid != owner:
            fail(f"{label} must be owned by uid {owner}")
        if exact_mode is not None and mode != exact_mode:
            fail(f"{label} must have mode {exact_mode:o}")
        if exact_mode is None and mode & 0o022:
            fail(f"{label} must not be group- or world-writable")
        require_no_acl(descriptor, label)

    def walk_directories(root, path, owner, leaf_owner, leaf_mode):
        descriptor = open_trust_root(root)
        validate_directory(descriptor, owner, "trusted root")
        path_components = relative_components(root, path)
        for index, component in enumerate(path_components):
            next_descriptor = open_directory(descriptor, component, "managed path")
            os.close(descriptor)
            descriptor = next_descriptor
            leaf = index == len(path_components) - 1
            validate_directory(
                descriptor,
                leaf_owner if leaf else owner,
                "managed directory",
                leaf_mode if leaf else None,
            )
        return descriptor

    def validate_password(data):
        if data.endswith(b"\n"):
            data = data[:-1]
        prefix = b"MSSQL_SA_PASSWORD="
        if not data.startswith(prefix) or any(byte in data for byte in (b"\0", b"\r", b"\n")):
            fail("the credential file must contain exactly one MSSQL_SA_PASSWORD assignment")
        try:
            password = data[len(prefix):].decode("utf-8", errors="strict")
        except UnicodeDecodeError:
            fail("the MSSQL password must be valid UTF-8")
        if not 8 <= len(password) <= 128:
            fail("the MSSQL password must contain 8 to 128 characters")
        classes = (
            any("A" <= character <= "Z" for character in password),
            any("a" <= character <= "z" for character in password),
            any("0" <= character <= "9" for character in password),
            any(not character.isalnum() for character in password),
        )
        if sum(classes) < 3:
            fail("the MSSQL password must use at least three required character classes")

    def validate_credential_descriptor(descriptor, owner):
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != owner
            or stat.S_IMODE(metadata.st_mode) != 0o600
            or metadata.st_nlink != 1
        ):
            fail("the credential file must be singly linked, owner-only, and mode 600")
        require_no_acl(descriptor, "credential file")
        chunks = []
        offset = 0
        while offset < 4097:
            chunk = os.pread(descriptor, 4097 - offset, offset)
            if not chunk:
                break
            chunks.append(chunk)
            offset += len(chunk)
        data = b"".join(chunks)
        if len(data) > 4096:
            fail("the credential file is unexpectedly large")
        validate_password(data)

    def open_credential(directory, trust_root, owner):
        directory_descriptor = walk_directories(
            trust_root, directory, owner, owner, 0o700
        )
        try:
            try:
                return os.open(
                    "environment",
                    os.O_RDONLY
                    | os.O_NONBLOCK
                    | os.O_NOFOLLOW
                    | os.O_CLOEXEC,
                    dir_fd=directory_descriptor,
                )
            except OSError:
                fail("the credential file must be a real file")
        finally:
            os.close(directory_descriptor)

    def validate_credentials(directory, trust_root, owner):
        credential_descriptor = open_credential(directory, trust_root, owner)
        try:
            validate_credential_descriptor(credential_descriptor, owner)
        finally:
            os.close(credential_descriptor)

    def validate_retained_credential(descriptor, owner, directory, trust_root):
        validate_credential_descriptor(descriptor, owner)
        configured_descriptor = open_credential(directory, trust_root, owner)
        try:
            validate_credential_descriptor(configured_descriptor, owner)
            retained = os.fstat(descriptor)
            configured = os.fstat(configured_descriptor)
            if (retained.st_dev, retained.st_ino) != (configured.st_dev, configured.st_ino):
                fail("the retained credential is not the configured credential file")
        finally:
            os.close(configured_descriptor)

    def validate_data(directory, trust_root, parent_owner, data_owner):
        descriptor = walk_directories(
            trust_root, directory, parent_owner, data_owner, 0o700
        )
        os.close(descriptor)

    if len(sys.argv) == 6 and sys.argv[1] == "--credential-fd":
        validate_retained_credential(
            int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
        )
    elif len(sys.argv) == 8:
        validate_credentials(sys.argv[1], sys.argv[2], int(sys.argv[3]))
        validate_data(sys.argv[4], sys.argv[5], int(sys.argv[6]), int(sys.argv[7]))
    else:
        fail("internal path-validator argument error")
  '';

in
{
  mssql =
    {
      credentialDirectory,
      credentialOwnerUid ? 0,
      credentialTrustRoot ? "/",
      dataDirectory,
      dataOwner,
      dataOwnerUid ? null,
      dataParentOwnerUid ? credentialOwnerUid,
      dataTrustRoot ? "/",
    }:
    assert isCanonicalAbsolute credentialDirectory && credentialDirectory != "/";
    assert isCanonicalAbsolute credentialTrustRoot;
    assert isDescendant credentialTrustRoot credentialDirectory;
    assert isCanonicalAbsolute dataDirectory && dataDirectory != "/" && !lib.hasInfix "," dataDirectory;
    assert isCanonicalAbsolute dataTrustRoot;
    assert isDescendant dataTrustRoot dataDirectory;
    pkgs.writeShellApplication {
      name = "mssql-server-launcher";
      passthru = {
        inherit descriptorSanitizerSource mssqlPathValidator;
      };
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        set -eu
        exec 3<&-

        [ "$#" -eq 0 ] || {
          echo "mssql-server: the launcher does not accept arguments" >&2
          exit 1
        }

        credential_directory=${lib.escapeShellArg credentialDirectory}
        credential_file="$credential_directory/environment"
        credential_owner_uid=${lib.escapeShellArg (toString credentialOwnerUid)}
        credential_trust_root=${lib.escapeShellArg credentialTrustRoot}
        data_directory=${lib.escapeShellArg dataDirectory}
        data_owner=${lib.escapeShellArg dataOwner}
        data_owner_uid=${lib.escapeShellArg (if dataOwnerUid == null then "" else toString dataOwnerUid)}
        data_parent_owner_uid=${lib.escapeShellArg (toString dataParentOwnerUid)}
        data_trust_root=${lib.escapeShellArg dataTrustRoot}
        docker=${pkgs.docker-client}/bin/docker
        docker_environment=${pkgs.coreutils}/bin/env
        fd_exec=${descriptorSanitizer}/bin/launchd-fd-exec

        fail() {
          echo "mssql-server: $*" >&2
          exit 1
        }

        if [ -z "$data_owner_uid" ]; then
          data_owner_uid=$("$fd_exec" -1 ${pkgs.coreutils}/bin/id -u -- "$data_owner") ||
            fail "the MSSQL data owner is unavailable"
        fi

        validate_paths() {
          "$fd_exec" -1 ${pkgs.python3}/bin/python3 -I ${mssqlPathValidator} \
            "$credential_directory" "$credential_trust_root" "$credential_owner_uid" \
            "$data_directory" "$data_trust_root" "$data_parent_owner_uid" "$data_owner_uid"
        }

        validate_credential_fd() {
          "$fd_exec" 3 ${pkgs.python3}/bin/python3 -I ${mssqlPathValidator} \
            --credential-fd 3 "$credential_owner_uid" \
            "$credential_directory" "$credential_trust_root"
        }

        docker_exec() {
          keep=$1
          shift
          "$fd_exec" "$keep" "$docker_environment" \
            DOCKER_CONFIG=/var/root/.docker \
            DOCKER_HOST=unix:///var/run/docker.sock \
            HOME=/var/root \
            PATH=/usr/bin:/bin:/usr/sbin:/sbin \
            "$docker" "$@"
        }

        validate_paths

        while ! docker_exec -1 info >/dev/null 2>&1; do
          echo "Waiting for Docker to be ready..."
          "$fd_exec" -1 ${pkgs.coreutils}/bin/sleep 5
        done

        image=mcr.microsoft.com/mssql/server:2022-latest
        docker_exec -1 pull "$image"
        image_id=$(docker_exec -1 image inspect --format '{{.Id}}' "$image") ||
          fail "the pulled MSSQL image identity is unavailable"
        case "$image_id" in
          sha256:*) image_hash=''${image_id#sha256:} ;;
          *) fail "the pulled MSSQL image identity is invalid" ;;
        esac
        [ "''${#image_hash}" -eq 64 ] ||
          fail "the pulled MSSQL image identity is invalid"
        case "$image_hash" in
          *[!0-9a-f]*) fail "the pulled MSSQL image identity is invalid" ;;
        esac

        # Make the daemon exercise the final writable bind as the image's
        # default user before removing the current container. The collision-safe
        # probe creates and deletes only its own empty sentinel.
        probe_command="data=/var/opt/mssql; probe=\"\$data/.nix-config-bind-probe.\$\$\"; test -d \"\$data\" && test -r \"\$data\" && test -w \"\$data\" && test -x \"\$data\" && (set -C; : >\"\$probe\") && rm -f \"\$probe\""
        validate_paths
        docker_exec -1 run --pull=never --rm \
          --mount "type=bind,source=$data_directory,target=/var/opt/mssql" \
          --entrypoint /bin/sh \
          "$image_id" \
          -c "$probe_command" ||
          fail "the MSSQL data bind is unavailable to Docker"

        # Recheck after the potentially long pull and mount probe, then retain
        # the validated credential object across container removal.
        validate_paths
        exec 3<"$credential_file" || fail "the credential file cannot be opened"
        validate_credential_fd
        existing_container=$(
          docker_exec -1 container ls --all \
            --filter 'name=^/mssql-server$' --format '{{.Names}}' 3<&-
        ) || fail "the existing MSSQL container state is unavailable"
        case "$existing_container" in
          "") ;;
          mssql-server)
            docker_exec -1 rm -f mssql-server 3<&- 2>/dev/null ||
              fail "the existing MSSQL container could not be removed"
            ;;
          *) fail "the existing MSSQL container state is ambiguous" ;;
        esac

        # Revalidate the stable, root-parented data path after removal. The run
        # client consumes the already-open credential object through FD 3.
        validate_paths 3<&-
        validate_credential_fd

        # The upstream image accepts the SA password only as an environment
        # variable. --env-file keeps its value out of this host process's argv;
        # Docker-daemon principals remain inside the credential trust boundary.
        docker_exec 3 run --pull=never -d \
          --name mssql-server \
          --restart unless-stopped \
          --publish 127.0.0.1:1433:1433/tcp \
          --mount "type=bind,source=$data_directory,target=/var/opt/mssql" \
          --env ACCEPT_EULA=Y \
          --env-file /dev/fd/3 \
          "$image_id"
      '';
    };

  vlcTelnet =
    {
      account,
      home,
      keychainService ? "nix-config.vlc-telnet",
      launcherFixtureSource ? null,
      port ? 4212,
      securityFixtureSource ? null,
      vlcBin,
      vlcHome,
    }:
    assert
      builtins.isString account
      && account != ""
      && !lib.hasInfix "\r" account
      && !lib.hasInfix "\n" account;
    assert
      builtins.isString keychainService
      && keychainService != ""
      && !lib.hasInfix "\r" keychainService
      && !lib.hasInfix "\n" keychainService;
    assert isCanonicalAbsolute home;
    assert builtins.isInt port && port >= 1 && port <= 65535;
    assert isCanonicalAbsolute vlcBin && lib.hasPrefix "${builtins.storeDir}/" vlcBin;
    assert isCanonicalAbsolute vlcHome && lib.hasPrefix "${builtins.storeDir}/" vlcHome;
    let
      safeEntitlementsSource = ''
        static int has_safe_entitlements(CFDictionaryRef information) {
            CFTypeRef raw = CFDictionaryGetValue(
                information, kSecCodeInfoEntitlements
            );
            CFTypeRef parsed = CFDictionaryGetValue(
                information, kSecCodeInfoEntitlementsDict
            );
            if (raw == NULL && parsed == NULL) return 0;
            if (
                raw == NULL
                || parsed == NULL
                || CFGetTypeID(raw) != CFDataGetTypeID()
                || CFDataGetLength((CFDataRef)raw) <= 0
                || CFGetTypeID(parsed) != CFDictionaryGetTypeID()
            ) {
                return -1;
            }

            CFDictionaryRef entitlements = (CFDictionaryRef)parsed;
            const CFStringRef unsafe[] = {
                CFSTR("com.apple.security.cs.allow-dyld-environment-variables"),
                CFSTR("com.apple.security.cs.disable-library-validation"),
                CFSTR("com.apple.security.get-task-allow"),
            };
            for (size_t index = 0; index < sizeof(unsafe) / sizeof(unsafe[0]); ++index) {
                if (CFDictionaryContainsKey(entitlements, unsafe[index])) return -1;
            }
            return 0;
        }
      '';
      entitlementValidatorSource = pkgs.writeText "validate-vlc-entitlements.c" ''
        #include <CoreFoundation/CoreFoundation.h>
        #include <Security/Security.h>
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>

        ${safeEntitlementsSource}

        static int fail(void) {
            fputs("vlc-entitlements: validation failed\n", stderr);
            return EXIT_FAILURE;
        }

        int main(int argc, char **argv) {
            if (argc != 2 || argv[1][0] != '/') return fail();
            CFURLRef url = CFURLCreateFromFileSystemRepresentation(
                kCFAllocatorDefault,
                (const UInt8 *)argv[1],
                (CFIndex)strlen(argv[1]),
                false
            );
            if (url == NULL) return fail();

            SecStaticCodeRef code = NULL;
            OSStatus status = SecStaticCodeCreateWithPath(
                url, kSecCSDefaultFlags, &code
            );
            CFRelease(url);
            if (status != errSecSuccess || code == NULL) {
                if (code != NULL) CFRelease(code);
                return fail();
            }
            if (
                SecStaticCodeCheckValidity(
                    code, kSecCSStrictValidate, NULL
                ) != errSecSuccess
            ) {
                CFRelease(code);
                return fail();
            }

            CFDictionaryRef information = NULL;
            status = SecCodeCopySigningInformation(
                code, kSecCSSigningInformation, &information
            );
            CFRelease(code);
            if (
                status != errSecSuccess
                || information == NULL
                || has_safe_entitlements(information) != 0
            ) {
                if (information != NULL) CFRelease(information);
                return fail();
            }
            CFRelease(information);
            return EXIT_SUCCESS;
        }
      '';
      # The security CLI hex-encodes an entire password when any byte is
      # non-printable. A separately hardened helper queries CFData directly;
      # its Security.framework state dies before the never-threaded parent maps
      # the bounded config pipe to FD 3 and becomes immutable VLC.
      helperSource = pkgs.writeText "vlc-telnet-keychain-helper.c" ''
        #define _DARWIN_C_SOURCE 1
        #include <CoreFoundation/CoreFoundation.h>
        #include <Security/Security.h>
        #include <errno.h>
        #include <fcntl.h>
        #include <libproc.h>
        #include <stdint.h>
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>
        #include <sys/proc_info.h>
        #include <sys/stat.h>
        #include <sys/types.h>
        #include <unistd.h>

        #define MAX_PASSWORD_SIZE 492

        static const char account_name[] = ${builtins.toJSON account};
        static const char service_name[] = ${builtins.toJSON keychainService};
        static const char expected_parent_path[] = "@EXPECTED_PARENT_PATH@";
        static pid_t authenticated_parent = -1;

        static const uint8_t config_prefix[] = {
            0xef, 0xbb, 0xbf,
            't', 'e', 'l', 'n', 'e', 't', '-',
            'p', 'a', 's', 's', 'w', 'o', 'r', 'd', '='
        };
        enum { MAX_CONFIG_SIZE = sizeof(config_prefix) + MAX_PASSWORD_SIZE + 1 };
        _Static_assert(
            MAX_CONFIG_SIZE <= _POSIX_PIPE_BUF,
            "the complete config must fit within the portable atomic pipe bound"
        );

        ${safeEntitlementsSource}

        static void wipe(void *memory, size_t length) {
            volatile uint8_t *bytes = memory;
            while (length-- > 0) *bytes++ = 0;
        }

        static int fail(const char *message) {
            (void)message;
            fputs("vlc-telnet: Keychain helper failed\n", stderr);
            return EXIT_FAILURE;
        }

        static int set_cloexec(int descriptor) {
            int flags = fcntl(descriptor, F_GETFD);
            if (flags < 0) return -1;
            return fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC);
        }

        static int write_all(int descriptor, const uint8_t *bytes, size_t length) {
            while (length > 0) {
                ssize_t written = write(descriptor, bytes, length);
                if (written < 0) {
                    if (errno == EINTR) continue;
                    return -1;
                }
                if (written == 0) return -1;
                bytes += (size_t)written;
                length -= (size_t)written;
            }
            return 0;
        }

        static int is_vlc_edge_whitespace(uint8_t byte) {
            // VLC 3.0.23's Lua common.strip treats these as C-locale %s.
            // CR and LF are rejected at every position below.
            return byte == ' ' || byte == '\t' || byte == '\v' || byte == '\f';
        }

        ${closeUnrelatedDescriptorsSource}

        static int validate_parent(void) {
            pid_t parent = getppid();
            if (parent <= 1) return -1;

            char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
            int length = proc_pidpath(parent, path, sizeof(path));
            if (
                length <= 0
                || (size_t)length >= sizeof(path)
                || strcmp(path, expected_parent_path) != 0
                || getppid() != parent
            ) {
                return -1;
            }

            int parent_value = parent;
            CFNumberRef parent_number = CFNumberCreate(
                kCFAllocatorDefault, kCFNumberIntType, &parent_value
            );
            if (parent_number == NULL) return -1;
            const void *keys[] = { kSecGuestAttributePid };
            const void *values[] = { parent_number };
            CFDictionaryRef attributes = CFDictionaryCreate(
                kCFAllocatorDefault, keys, values, 1,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks
            );
            CFRelease(parent_number);
            if (attributes == NULL) return -1;

            SecCodeRef code = NULL;
            OSStatus status = SecCodeCopyGuestWithAttributes(
                NULL, attributes, kSecCSDefaultFlags, &code
            );
            CFRelease(attributes);
            if (status != errSecSuccess || code == NULL) {
                if (code != NULL) CFRelease(code);
                return -1;
            }
            if (SecCodeCheckValidity(code, kSecCSStrictValidate, NULL) != errSecSuccess) {
                CFRelease(code);
                return -1;
            }

            CFDictionaryRef information = NULL;
            status = SecCodeCopySigningInformation(
                code,
                kSecCSSigningInformation | kSecCSDynamicInformation,
                &information
            );
            CFRelease(code);
            if (status != errSecSuccess || information == NULL) {
                if (information != NULL) CFRelease(information);
                return -1;
            }

            uint32_t static_flags = 0;
            uint32_t dynamic_flags = 0;
            CFNumberRef static_number = (CFNumberRef)CFDictionaryGetValue(
                information, kSecCodeInfoFlags
            );
            CFNumberRef dynamic_number = (CFNumberRef)CFDictionaryGetValue(
                information, kSecCodeInfoStatus
            );
            int valid = has_safe_entitlements(information) == 0
                && static_number != NULL
                && dynamic_number != NULL
                && CFGetTypeID(static_number) == CFNumberGetTypeID()
                && CFGetTypeID(dynamic_number) == CFNumberGetTypeID()
                && CFNumberGetValue(
                    static_number, kCFNumberSInt32Type, &static_flags
                )
                && CFNumberGetValue(
                    dynamic_number, kCFNumberSInt32Type, &dynamic_flags
                );
            CFRelease(information);

            const uint32_t required_static =
                kSecCodeSignatureRuntime | kSecCodeSignatureLibraryValidation;
            const uint32_t required_dynamic =
                kSecCodeStatusValid | kSecCodeStatusHard | kSecCodeStatusKill;
            if (
                !valid
                || (static_flags & required_static) != required_static
                || (dynamic_flags & required_dynamic) != required_dynamic
                || (dynamic_flags & kSecCodeStatusDebugged) != 0
                || getppid() != parent
            ) {
                return -1;
            }
            authenticated_parent = parent;
            return 0;
        }

        static int validate_output_descriptor(void) {
            struct stat metadata;
            int flags = fcntl(3, F_GETFL);
            if (
                flags < 0
                || (flags & O_ACCMODE) != O_WRONLY
                || fstat(3, &metadata) < 0
                || !S_ISFIFO(metadata.st_mode)
                || set_cloexec(3) < 0
            ) {
                return -1;
            }
            return close_unrelated_descriptors(3);
        }

        static int load_password(uint8_t *buffer, size_t capacity, size_t *length) {
            CFStringRef account = CFStringCreateWithBytes(
                kCFAllocatorDefault,
                (const UInt8 *)account_name,
                (CFIndex)strlen(account_name),
                kCFStringEncodingUTF8,
                false
            );
            CFStringRef service = CFStringCreateWithBytes(
                kCFAllocatorDefault,
                (const UInt8 *)service_name,
                (CFIndex)strlen(service_name),
                kCFStringEncodingUTF8,
                false
            );
            if (account == NULL || service == NULL) {
                if (account != NULL) CFRelease(account);
                if (service != NULL) CFRelease(service);
                return -1;
            }

            const void *match_keys[] = {
                kSecClass, kSecAttrAccount, kSecAttrService,
                kSecReturnPersistentRef, kSecMatchLimit, kSecUseAuthenticationUI
            };
            const void *match_values[] = {
                kSecClassGenericPassword, account, service,
                kCFBooleanTrue, kSecMatchLimitAll, kSecUseAuthenticationUISkip
            };
            CFDictionaryRef match_query = CFDictionaryCreate(
                kCFAllocatorDefault, match_keys, match_values, 6,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks
            );
            CFRelease(account);
            CFRelease(service);
            if (match_query == NULL) {
                return -1;
            }

            CFTypeRef match_result = NULL;
            OSStatus status = SecItemCopyMatching(match_query, &match_result);
            CFRelease(match_query);
            if (getppid() != authenticated_parent) {
                if (match_result != NULL) CFRelease(match_result);
                return -1;
            }
            if (status != errSecSuccess || match_result == NULL) {
                if (match_result != NULL) CFRelease(match_result);
                return -1;
            }
            if (CFGetTypeID(match_result) != CFArrayGetTypeID()) {
                CFRelease(match_result);
                return -1;
            }
            CFArrayRef matches = (CFArrayRef)match_result;
            if (CFArrayGetCount(matches) != 1) {
                CFRelease(match_result);
                return -1;
            }
            CFTypeRef persistent_ref = CFArrayGetValueAtIndex(matches, 0);
            if (CFGetTypeID(persistent_ref) != CFDataGetTypeID()) {
                CFRelease(match_result);
                return -1;
            }

            const void *value_keys[] = {
                kSecValuePersistentRef, kSecReturnData, kSecUseAuthenticationUI
            };
            const void *value_values[] = {
                persistent_ref, kCFBooleanTrue, kSecUseAuthenticationUISkip
            };
            CFDictionaryRef value_query = CFDictionaryCreate(
                kCFAllocatorDefault, value_keys, value_values, 3,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks
            );
            CFRelease(match_result);
            if (value_query == NULL) {
                return -1;
            }

            CFTypeRef result = NULL;
            status = SecItemCopyMatching(value_query, &result);
            CFRelease(value_query);
            if (getppid() != authenticated_parent) {
                if (result != NULL) CFRelease(result);
                return -1;
            }
            if (status != errSecSuccess || result == NULL) {
                if (result != NULL) CFRelease(result);
                return -1;
            }
            if (CFGetTypeID(result) != CFDataGetTypeID()) {
                CFRelease(result);
                return -1;
            }

            CFIndex item_length = CFDataGetLength((CFDataRef)result);
            if (item_length < 0) {
                CFRelease(result);
                return -1;
            }
            if ((uint64_t)item_length > (uint64_t)capacity) {
                *length = capacity;
            } else {
                *length = (size_t)item_length;
                if (*length > 0) {
                    memcpy(buffer, CFDataGetBytePtr((CFDataRef)result), *length);
                }
            }
            CFRelease(result);
            return 0;
        }

        static const char *validate_password(const uint8_t *password, size_t length) {
            if (length < 1 || length > MAX_PASSWORD_SIZE) {
                return "Keychain password length is outside the supported range";
            }
            if (length == 1 && password[0] == 0x04) {
                return "Keychain password is VLC's telnet quit byte";
            }
            if (
                is_vlc_edge_whitespace(password[0])
                || is_vlc_edge_whitespace(password[length - 1])
            ) {
                return "Keychain password has whitespace stripped by VLC";
            }
            for (size_t index = 0; index < length; ++index) {
                if (password[index] == 0 || password[index] == '\r' || password[index] == '\n') {
                    return "Keychain password contains a forbidden byte";
                }
            }
            CFStringRef decoded = CFStringCreateWithBytes(
                kCFAllocatorDefault,
                password,
                (CFIndex)length,
                kCFStringEncodingUTF8,
                false
            );
            if (decoded == NULL) return "Keychain password is not valid UTF-8";
            CFRelease(decoded);
            return NULL;
        }

        static int write_config(void) {
            uint8_t password[MAX_PASSWORD_SIZE + 1] = {0};
            size_t password_length = 0;
            if (load_password(password, sizeof(password), &password_length) != 0) {
                wipe(password, sizeof(password));
                return fail("Keychain password retrieval failed");
            }
            const char *validation_error = validate_password(password, password_length);
            if (validation_error != NULL) {
                wipe(password, sizeof(password));
                return fail(validation_error);
            }

            uint8_t config[MAX_CONFIG_SIZE] = {0};
            size_t config_length = 0;
            memcpy(config, config_prefix, sizeof(config_prefix));
            config_length += sizeof(config_prefix);
            memcpy(config + config_length, password, password_length);
            config_length += password_length;
            config[config_length++] = '\n';
            wipe(password, sizeof(password));

            if (getppid() != authenticated_parent) {
                wipe(config, sizeof(config));
                return fail("Keychain helper parent changed");
            }
            int status = write_all(3, config, config_length);
            wipe(config, sizeof(config));
            if (status != 0) return fail("could not write the VLC config pipe");
            return EXIT_SUCCESS;
        }

        int main(int argc, char **argv) {
            (void)argv;
            if (argc != 1) return fail("invalid Keychain helper invocation");
            if (validate_output_descriptor() != 0 || validate_parent() != 0) {
                return fail("Keychain helper authentication failed");
            }
            int status = write_config();
            close(3);
            return status;
        }
      '';

      launcherSource = pkgs.writeText "vlc-telnet-launcher.c" ''
        #define _DARWIN_C_SOURCE 1
        #include <errno.h>
        #include <fcntl.h>
        #include <limits.h>
        #include <libproc.h>
        #include <pthread.h>
        #include <spawn.h>
        #include <stdint.h>
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>
        #include <sys/proc_info.h>
        #include <sys/stat.h>
        #include <sys/types.h>
        #include <sys/wait.h>
        #include <unistd.h>

        static const char helper_bin[] = "@HELPER_PATH@";
        static const char vlc_bin[] = ${builtins.toJSON vlcBin};
        static const char vlc_port[] = ${builtins.toJSON "--telnet-port=${toString port}"};
        static char helper_home[] = ${builtins.toJSON "HOME=${home}"};
        static char helper_logname[] = ${builtins.toJSON "LOGNAME=${account}"};
        static char helper_path[] = "PATH=/usr/bin:/bin:/usr/sbin:/sbin";
        static char helper_user[] = ${builtins.toJSON "USER=${account}"};
        static char vlc_home[] = ${builtins.toJSON "HOME=${vlcHome}"};
        static char vlc_logname[] = ${builtins.toJSON "LOGNAME=${account}"};
        static char vlc_path[] = "PATH=/usr/bin:/bin:/usr/sbin:/sbin";
        static char vlc_user[] = ${builtins.toJSON "USER=${account}"};
        static char *vlc_environment[] = {
            vlc_home, vlc_logname, vlc_path, vlc_user, NULL
        };

        static int fail(const char *message) {
            fprintf(stderr, "vlc-telnet: %s\n", message);
            return EXIT_FAILURE;
        }

        static int set_cloexec(int descriptor) {
            int flags = fcntl(descriptor, F_GETFD);
            if (flags < 0) return -1;
            return fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC);
        }

        static int make_pipe(int descriptors[2]) {
            if (pipe(descriptors) < 0) return -1;
            if (set_cloexec(descriptors[0]) < 0 || set_cloexec(descriptors[1]) < 0) {
                close(descriptors[0]);
                close(descriptors[1]);
                return -1;
            }
            return 0;
        }

        ${closeUnrelatedDescriptorsSource}

        static int record_standard_descriptors(int open_descriptors[3]) {
            for (int descriptor = STDIN_FILENO; descriptor <= STDERR_FILENO; ++descriptor) {
                errno = 0;
                if (fcntl(descriptor, F_GETFD) >= 0) {
                    open_descriptors[descriptor] = 1;
                } else if (errno == EBADF) {
                    open_descriptors[descriptor] = 0;
                } else {
                    return -1;
                }
            }
            return 0;
        }

        static int require_single_thread(void) {
            if (pthread_is_threaded_np() != 0) return -1;
            uint64_t threads[2] = {0};
            errno = 0;
            int bytes = proc_pidinfo(
                getpid(), PROC_PIDLISTTHREADS, 0, threads, sizeof(threads)
            );
            if (bytes != PROC_PIDLISTTHREADS_SIZE || errno != 0) return -1;
            return 0;
        }

        static int validate_fifo(int descriptor, int access_mode) {
            struct stat metadata;
            int flags = fcntl(descriptor, F_GETFL);
            return flags >= 0
                && (flags & O_ACCMODE) == access_mode
                && fstat(descriptor, &metadata) == 0
                && S_ISFIFO(metadata.st_mode) ? 0 : -1;
        }

        ${lib.optionalString (securityFixtureSource != null) ''
          static int add_fixture_environment(
              const char *name,
              char *buffer,
              size_t capacity,
              char **environment,
              size_t *count
          ) {
              const char *value = getenv(name);
              if (value == NULL) return 0;
              int length = snprintf(buffer, capacity, "%s=%s", name, value);
              if (length < 0 || (size_t)length >= capacity) return -1;
              environment[(*count)++] = buffer;
              return 0;
          }
        ''}

        static int spawn_helper(
            int writer,
            const int open_standard_descriptors[3],
            pid_t *child
        ) {
            posix_spawn_file_actions_t actions;
            int status = posix_spawn_file_actions_init(&actions);
            if (status != 0) return status;

            for (int descriptor = STDIN_FILENO; descriptor <= STDERR_FILENO; ++descriptor) {
                if (!open_standard_descriptors[descriptor]) continue;
                status = posix_spawn_file_actions_addinherit_np(&actions, descriptor);
                if (status != 0) goto cleanup_actions;
            }
            status = posix_spawn_file_actions_adddup2(&actions, writer, 3);
            if (status != 0) goto cleanup_actions;

            posix_spawnattr_t attributes;
            status = posix_spawnattr_init(&attributes);
            if (status != 0) goto cleanup_actions;
            status = posix_spawnattr_setflags(
                &attributes,
                POSIX_SPAWN_CLOEXEC_DEFAULT
            );
            if (status != 0) goto cleanup_attributes;

            char *helper_arguments[] = { (char *)helper_bin, NULL };
            char fixture_environment[8][PATH_MAX + 64] = {{0}};
            char *helper_environment[13] = {
                helper_home, helper_logname, helper_path, helper_user, NULL
            };
            size_t environment_count = 4;
            (void)fixture_environment;
            (void)environment_count;
            ${lib.optionalString (securityFixtureSource != null) ''
              const char *fixture_names[] = {
                  "SERVICE_TEST_KEYCHAIN_DUPLICATE",
                  "SERVICE_TEST_KEYCHAIN_FAIL",
                  "SERVICE_TEST_KEYCHAIN_LOG",
                  "SERVICE_TEST_KEYCHAIN_OPEN_SECURITY_FD",
                  "SERVICE_TEST_KEYCHAIN_SIGNAL",
                  "SERVICE_TEST_KEYCHAIN_VALUE_FAIL",
                  "SERVICE_TEST_SECRET_FILE",
                  "SERVICE_TEST_SECURITY_FAULT",
                  NULL
              };
              for (size_t index = 0; fixture_names[index] != NULL; ++index) {
                  if (add_fixture_environment(
                      fixture_names[index],
                      fixture_environment[index],
                      sizeof(fixture_environment[index]),
                      helper_environment,
                      &environment_count
                  ) != 0) {
                      status = E2BIG;
                      goto cleanup_attributes;
                  }
              }
              helper_environment[environment_count] = NULL;
            ''}
            status = posix_spawn(
                child, helper_bin, &actions, &attributes,
                helper_arguments, helper_environment
            );

        cleanup_attributes:
            posix_spawnattr_destroy(&attributes);
        cleanup_actions:
            posix_spawn_file_actions_destroy(&actions);
            return status;
        }

        static int wait_for_helper(pid_t child) {
            int status;
            pid_t waited;
            do {
                waited = waitpid(child, &status, 0);
            } while (waited < 0 && errno == EINTR);
            if (
                waited != child
                || !WIFEXITED(status)
                || WEXITSTATUS(status) != EXIT_SUCCESS
            ) {
                return -1;
            }
            return 0;
        }

        static int normalize_config_descriptor(int descriptor) {
            if (validate_fifo(descriptor, O_RDONLY) != 0) {
                close(descriptor);
                return -1;
            }
            if (descriptor == 3) {
                return set_cloexec(3);
            }
            close(3);
            int normalized = fcntl(descriptor, F_DUPFD_CLOEXEC, 3);
            close(descriptor);
            return normalized == 3 ? 0 : -1;
        }

        static int validate_final_descriptors(
            const int open_standard_descriptors[3]
        ) {
            struct proc_fdinfo descriptors[8];
            int bytes = list_descriptors(
                descriptors, sizeof(descriptors) / sizeof(descriptors[0])
            );
            if (bytes < 0) return -1;
            int count = bytes / (int)sizeof(descriptors[0]);
            int seen[4] = {0};
            for (int index = 0; index < count; ++index) {
                int descriptor = descriptors[index].proc_fd;
                if (descriptor < 0 || descriptor > 3) return -1;
                seen[descriptor] = 1;
            }
            if (seen[3] != 1 || validate_fifo(3, O_RDONLY) != 0) return -1;
            for (int descriptor = 0; descriptor <= 2; ++descriptor) {
                if (seen[descriptor] != open_standard_descriptors[descriptor]) return -1;
            }
            return 0;
        }

        static int execute_vlc(void) {
            int flags = fcntl(3, F_GETFD);
            if (flags < 0 || fcntl(3, F_SETFD, flags & ~FD_CLOEXEC) < 0) {
                close(3);
                return -1;
            }
            char *arguments[] = {
                (char *)vlc_bin,
                "-I",
                "telnet",
                "--no-ignore-config",
                "--config=/dev/fd/3",
                "--telnet-host=127.0.0.1",
                (char *)vlc_port,
                NULL
            };
            execve(vlc_bin, arguments, vlc_environment);
            close(3);
            return -1;
        }

        int main(int argc, char **argv) {
            (void)argv;
            if (argc != 1) return fail("the launcher does not accept arguments");
            if (require_single_thread() != 0) {
                return fail("the launcher is not safely single-threaded");
            }
            if (close_unrelated_descriptors(-1) != 0) {
                return fail("could not close inherited descriptors");
            }
            int open_standard_descriptors[3];
            if (record_standard_descriptors(open_standard_descriptors) != 0) {
                return fail("could not inspect standard descriptors");
            }
            int descriptors[2];
            if (make_pipe(descriptors) < 0) {
                return fail("could not create the VLC config pipe");
            }
            long pipe_buffer = fpathconf(descriptors[1], _PC_PIPE_BUF);
            if (pipe_buffer < _POSIX_PIPE_BUF) {
                close(descriptors[0]);
                close(descriptors[1]);
                return fail("the VLC config exceeds the atomic pipe bound");
            }
            int helper_writer = fcntl(descriptors[1], F_DUPFD_CLOEXEC, 4);
            close(descriptors[1]);
            if (helper_writer < 4) {
                close(descriptors[0]);
                if (helper_writer >= 0) close(helper_writer);
                return fail("could not prepare the Keychain helper pipe");
            }

            pid_t child = 0;
            int spawn_status = spawn_helper(
                helper_writer, open_standard_descriptors, &child
            );
            close(helper_writer);
            if (spawn_status != 0 || child <= 0 || wait_for_helper(child) != 0) {
                close(descriptors[0]);
                return fail("Keychain password retrieval failed");
            }
            if (require_single_thread() != 0) {
                close(descriptors[0]);
                return fail("the launcher is not safely single-threaded");
            }
            if (normalize_config_descriptor(descriptors[0]) != 0) {
                return fail("could not prepare the VLC config descriptor");
            }
            if (
                close_unrelated_descriptors(3) != 0
                || validate_final_descriptors(open_standard_descriptors) != 0
                || require_single_thread() != 0
            ) {
                close(3);
                return fail("could not isolate the VLC config descriptor");
            }
            (void)execute_vlc();
            close(3);
            return fail("could not execute VLC");
        }
      '';
    in
    pkgs.runCommandCC "vlc-telnet-launcher"
      {
        passthru = {
          inherit entitlementValidatorSource helperSource;
          source = launcherSource;
        };
      }
      ''
        mkdir -p "$out/bin"
        mkdir -p "$out/libexec"
        substitute ${launcherSource} launcher.c \
          --replace-fail @HELPER_PATH@ "$out/libexec/vlc-telnet-keychain-helper"
        substitute ${helperSource} helper.c \
          --replace-fail @EXPECTED_PARENT_PATH@ "$out/bin/vlc-telnet-launcher"
        "$CC" -std=c11 -Wall -Wextra -Werror \
          launcher.c \
          ${
            lib.optionalString (launcherFixtureSource != null) (
              lib.escapeShellArg (toString launcherFixtureSource)
            )
          } \
          -o "$out/bin/vlc-telnet-launcher"
        "$CC" -std=c11 -Wall -Wextra -Werror \
          helper.c \
          ${
            lib.optionalString (securityFixtureSource != null) (
              lib.escapeShellArg (toString securityFixtureSource)
            )
          } \
          -framework CoreFoundation -framework Security \
          -o "$out/libexec/vlc-telnet-keychain-helper"
        "$CC" -std=c11 -Wall -Wextra -Werror \
          ${entitlementValidatorSource} \
          -framework CoreFoundation -framework Security \
          -o validate-vlc-entitlements

        for binary in \
          "$out/bin/vlc-telnet-launcher" \
          "$out/libexec/vlc-telnet-keychain-helper"; do
          /usr/bin/codesign --force --sign - \
            --options runtime,library --timestamp=none "$binary"
          /usr/bin/codesign --verify --strict --verbose=4 "$binary"
          signature=$(/usr/bin/codesign --display --verbose=4 "$binary" 2>&1)
          grep -E 'flags=.*\([^)]*adhoc' <<<"$signature" >/dev/null
          grep -E 'flags=.*\([^)]*library-validation' <<<"$signature" >/dev/null
          grep -E 'flags=.*\([^)]*runtime' <<<"$signature" >/dev/null
          ./validate-vlc-entitlements "$binary"
        done
      '';
}
