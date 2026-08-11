{
  darwinConfigurations,
  pkgs,
  src,
}:

let
  inherit (pkgs) lib;

  fakeDockerProgram = pkgs.writeText "fake-docker.py" ''
    import base64
    import fcntl
    import json
    import os
    import pathlib
    import subprocess
    import sys

    def open_fds():
        result = []
        for entry in os.listdir("/dev/fd"):
            if not entry.isdecimal():
                continue
            descriptor = int(entry)
            try:
                os.fstat(descriptor)
            except OSError:
                continue
            result.append(descriptor)
        return sorted(result)

    def swap(path):
        target = pathlib.Path(path)
        saved = target.with_name(target.name + ".trusted")
        target.rename(saved)
        target.symlink_to(saved.name, target_is_directory=True)

    arguments = sys.argv[1:]
    inherited_fds = open_fds()
    credential_file = pathlib.Path("service-trust/nix-config/mssql/environment")
    credential_bytes = b"" if arguments == ["info"] else credential_file.read_bytes()
    secret = credential_bytes.removeprefix(b"MSSQL_SA_PASSWORD=").rstrip(b"\n")
    secret_variants = {secret} if secret else set()
    if len(secret) >= 8:
        secret_variants.update(
            secret[index:index + 8] for index in range(len(secret) - 7)
        )
    encoded_variants = set()
    for value in secret_variants:
        if len(value) < 8:
            continue
        encoded_variants.update({
            value.hex().encode(),
            value.hex().upper().encode(),
            base64.b64encode(value),
            base64.b64encode(value).rstrip(b"="),
        })
    secret_variants.update(encoded_variants)
    short_canary = secret[:7]
    short_raw_variants = set()
    if len(short_canary) == 7 and all(byte >= 0x80 for byte in short_canary):
        short_raw_variants = {
            short_canary[start:stop]
            for start in range(len(short_canary))
            for stop in range(start + 1, len(short_canary) + 1)
        }
    short_encoded_variants = set()
    for value in short_raw_variants:
        short_encoded_variants.update({
            value.hex().encode(),
            value.hex().upper().encode(),
            base64.b64encode(value),
            base64.b64encode(value).rstrip(b"="),
            base64.urlsafe_b64encode(value),
            base64.urlsafe_b64encode(value).rstrip(b"="),
        })
    secret_variants.update(short_raw_variants)

    encoded_left_token_bytes = frozenset(
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/_-"
    )
    encoded_right_token_bytes = encoded_left_token_bytes | {ord("=")}

    def contains_bounded(haystack, needle):
        offset = 0
        while True:
            index = haystack.find(needle, offset)
            if index < 0:
                return False
            end = index + len(needle)
            if (
                (index == 0 or haystack[index - 1] not in encoded_left_token_bytes)
                and (
                    end == len(haystack)
                    or haystack[end] not in encoded_right_token_bytes
                )
            ):
                return True
            offset = index + 1

    environment = dict(os.environ)
    environment.pop("LC_CTYPE", None)
    environment.pop("__CF_USER_TEXT_ENCODING", None)
    secret_value_env_keys = sorted(
        key
        for key, value in os.environ.items()
        if key == "MSSQL_SA_PASSWORD"
        or any(variant and variant in value.encode() for variant in secret_variants)
        or any(
            contains_bounded(value.encode(), variant)
            for variant in short_encoded_variants
        )
    )
    env_file_matches_fixture = None
    env_file_is_configured_object = None
    env_file_access_mode = None
    if "--env-file" in arguments:
        env_file = pathlib.Path(arguments[arguments.index("--env-file") + 1])
        env_file_matches_fixture = env_file.read_bytes() == credential_bytes
        inherited = os.fstat(3)
        configured = credential_file.stat()
        env_file_access_mode = fcntl.fcntl(3, fcntl.F_GETFL) & os.O_ACCMODE
        env_file_is_configured_object = (
            inherited.st_dev, inherited.st_ino
        ) == (configured.st_dev, configured.st_ino)
    with open("docker.jsonl", "a", encoding="utf-8") as log:
        json.dump(
            {
                "argv": arguments,
                "env_file_access_mode": env_file_access_mode,
                "env_file_is_configured_object": env_file_is_configured_object,
                "env_file_matches_fixture": env_file_matches_fixture,
                "environment": dict(sorted(environment.items())),
                "open_fds": inherited_fds,
                "secret_value_env_keys": secret_value_env_keys,
            },
            log,
            separators=(",", ":"),
        )
        log.write("\n")

    if arguments == ["info"] and pathlib.Path("docker-info-retry").exists():
        attempts_path = pathlib.Path("docker-info-attempts")
        attempts = int(attempts_path.read_text()) if attempts_path.exists() else 0
        attempts += 1
        attempts_path.write_text(str(attempts))
        if attempts == 1:
            raise SystemExit(42)
    if arguments[:1] == ["pull"] and pathlib.Path("docker-swap-parent").exists():
        swap("service-trust/nix-config")
    if arguments[:3] == ["run", "--pull=never", "--rm"] and pathlib.Path("docker-fail-mount-check").exists():
        raise SystemExit(42)
    if arguments[:3] == ["run", "--pull=never", "--rm"] and pathlib.Path("docker-swap-after-mount").exists():
        swap("service-trust/mssql-data/data")
    if arguments[:1] == ["rm"] and pathlib.Path("docker-fail-rm").exists():
        raise SystemExit(42)
    if arguments[:1] == ["rm"] and pathlib.Path("docker-swap-data").exists():
        swap("service-trust/mssql-data/data")
    if arguments[:1] == ["rm"] and pathlib.Path("docker-mutate-envfile").exists():
        retained = credential_file.with_name("environment.retained")
        credential_file.rename(retained)
        credential_file.write_bytes(credential_bytes)
        credential_file.chmod(0o600)
    if arguments[:1] == ["rm"] and pathlib.Path("docker-mutate-envfile-content").exists():
        credential_file.write_bytes(b"MSSQL_SA_PASSWORD=abcdefgh\n")
    if arguments[:1] == ["rm"] and pathlib.Path("docker-mutate-envfile-mode").exists():
        credential_file.chmod(0o400)
    if arguments[:1] == ["rm"] and pathlib.Path("docker-mutate-envfile-acl").exists():
        subprocess.run(
            ["/bin/chmod", "+a", "everyone deny delete", credential_file],
            check=True,
        )
    image_id = "sha256:" + "a" * 64
    if arguments == [
        "image", "inspect", "--format", "{{.Id}}",
        "mcr.microsoft.com/mssql/server:2022-latest",
    ]:
        print(
            "invalid-image-id"
            if pathlib.Path("docker-invalid-image-id").exists()
            else image_id
        )
    if arguments == [
        "container", "ls", "--all", "--filter", "name=^/mssql-server$",
        "--format", "{{.Names}}",
    ]:
        if pathlib.Path("docker-container-ambiguous").exists():
            print("mssql-server\nmssql-server-copy")
        elif not pathlib.Path("docker-container-absent").exists():
            print("mssql-server")
  '';

  fakeValidatorRunnerProgram = pkgs.writeText "fake-validator-runner.py" ''
    import os
    import pathlib
    import runpy
    import stat
    import sys
    import types

    validator, *arguments = sys.argv[1:]
    tracked_paths = {}
    real_open = os.open
    real_fstat = os.fstat

    def tracked_open(path, flags, mode=0o777, *, dir_fd=None):
        descriptor = real_open(path, flags, mode, dir_fd=dir_fd)
        path = os.fsdecode(path)
        if os.path.isabs(path):
            tracked_paths[descriptor] = os.path.normpath(path)
        elif dir_fd in tracked_paths:
            tracked_paths[descriptor] = os.path.normpath(
                os.path.join(tracked_paths[dir_fd], path)
            )
        return descriptor

    credential_directory = (
        arguments[3] if arguments[:1] == ["--credential-fd"] else arguments[0]
    )
    credential_file = os.path.join(credential_directory, "environment")
    credential_intermediate = os.path.dirname(credential_directory)
    data_directory = None if arguments[:1] == ["--credential-fd"] else arguments[3]
    data_intermediate = None if data_directory is None else os.path.dirname(data_directory)

    def synthetic_fstat(descriptor):
        metadata = real_fstat(descriptor)
        path = tracked_paths.get(descriptor)
        owner = metadata.st_uid
        if path == data_directory and stat.S_ISDIR(metadata.st_mode):
            owner = os.getuid() + 2
            pathlib.Path("validator-data-owner-observed").touch()
        elif (
            path == credential_file
            and stat.S_ISREG(metadata.st_mode)
            and pathlib.Path("validator-wrong-credential-file-owner").exists()
        ):
            owner = os.getuid() + 1
            pathlib.Path("validator-credential-file-owner-observed").touch()
        elif (
            path == credential_intermediate
            and stat.S_ISDIR(metadata.st_mode)
            and pathlib.Path("validator-wrong-credential-intermediate-owner").exists()
        ):
            owner = os.getuid() + 1
            pathlib.Path("validator-credential-intermediate-owner-observed").touch()
        elif (
            path == data_intermediate
            and stat.S_ISDIR(metadata.st_mode)
            and pathlib.Path("validator-wrong-data-intermediate-owner").exists()
        ):
            owner = os.getuid() + 1
            pathlib.Path("validator-data-intermediate-owner-observed").touch()
        if owner == metadata.st_uid:
            return metadata
        return types.SimpleNamespace(
            st_dev=metadata.st_dev,
            st_ino=metadata.st_ino,
            st_mode=metadata.st_mode,
            st_nlink=metadata.st_nlink,
            st_uid=owner,
        )

    os.open = tracked_open
    os.fstat = synthetic_fstat
    if pathlib.Path("validator-short-pread").exists():
        real_pread = os.pread
        os.pread = lambda descriptor, count, offset: real_pread(
            descriptor, min(count, 3), offset
        )
    sys.argv = [validator, *arguments]
    runpy.run_path(validator, run_name="__main__")
  '';

  fakeValidatorProgram = pkgs.writeText "fake-validator.py" ''
    import json
    import os
    import pathlib
    import sys

    def open_fds():
        result = []
        for entry in os.listdir("/dev/fd"):
            if not entry.isdecimal():
                continue
            descriptor = int(entry)
            try:
                os.fstat(descriptor)
            except OSError:
                continue
            result.append(descriptor)
        return sorted(result)

    phase = "credential" if "--credential-fd" in sys.argv[1:] else "paths"
    environment = dict(os.environ)
    environment.pop("LC_CTYPE", None)
    environment.pop("__CF_USER_TEXT_ENCODING", None)
    if environment:
        raise SystemExit("fake-validator: inherited environment")
    docker_calls = len(pathlib.Path("docker.jsonl").read_text().splitlines())
    descriptors = open_fds()
    with open("validator.jsonl", "a", encoding="utf-8") as log:
        json.dump(
            {
                "argv": sys.argv[1:],
                "docker_calls": docker_calls,
                "environment": dict(sorted(environment.items())),
                "open_fds": descriptors,
                "phase": phase,
            },
            log,
            separators=(",", ":"),
        )
        log.write("\n")
    os.execv(
        "${pkgs.python3}/bin/python3",
        [
            "${pkgs.python3}/bin/python3",
            "-I",
            ${builtins.toJSON "${fakeValidatorRunnerProgram}"},
            *sys.argv[2:],
        ],
    )
  '';
  fakeValidatorPython = pkgs.writeTextFile {
    name = "python3";
    destination = "/bin/python3";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      import runpy
      runpy.run_path(${builtins.toJSON "${fakeValidatorProgram}"}, run_name="__main__")
    '';
  };
  fakeDocker = pkgs.writeTextFile {
    name = "docker";
    destination = "/bin/docker";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      import runpy
      runpy.run_path(${builtins.toJSON "${fakeDockerProgram}"}, run_name="__main__")
    '';
  };
  recordingId = pkgs.writeTextFile {
    name = "recording-id";
    destination = "/bin/id";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      import json
      import os
      import pathlib
      import sys

      descriptors = []
      for entry in os.listdir("/dev/fd"):
          if entry.isdecimal():
              try:
                  os.fstat(int(entry))
              except OSError:
                  continue
              descriptors.append(int(entry))
      environment = dict(os.environ)
      environment.pop("LC_CTYPE", None)
      environment.pop("__CF_USER_TEXT_ENCODING", None)
      record = {
          "argv": sys.argv[1:],
          "environment": environment,
          "open_fds": sorted(descriptors),
      }
      pathlib.Path("id.json").write_text(json.dumps(record, sort_keys=True))
      print(os.getuid() + 2)
    '';
  };
  recordingSleep = pkgs.writeTextFile {
    name = "recording-sleep";
    destination = "/bin/sleep";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      import json
      import os
      import pathlib
      import sys

      descriptors = []
      for entry in os.listdir("/dev/fd"):
          if entry.isdecimal():
              try:
                  os.fstat(int(entry))
              except OSError:
                  continue
              descriptors.append(int(entry))
      environment = dict(os.environ)
      environment.pop("LC_CTYPE", None)
      environment.pop("__CF_USER_TEXT_ENCODING", None)
      with pathlib.Path("sleep.jsonl").open("a", encoding="utf-8") as log:
          json.dump(
              {
                  "argv": sys.argv[1:],
                  "environment": environment,
                  "open_fds": sorted(descriptors),
              },
              log,
              separators=(",", ":"),
          )
          log.write("\n")
    '';
  };
  recordingCoreutils = pkgs.symlinkJoin {
    name = "recording-coreutils";
    paths = [ pkgs.coreutils ];
    postBuild = ''
      rm "$out/bin/id"
      ln -s ${recordingId}/bin/id "$out/bin/id"
      rm "$out/bin/sleep"
      ln -s ${recordingSleep}/bin/sleep "$out/bin/sleep"
    '';
  };
  testPkgs = pkgs // {
    coreutils = recordingCoreutils;
    docker-client = fakeDocker;
    python3 = fakeValidatorPython;
  };
  launchers = import ../../config/launchd-service-launchers.nix {
    inherit lib;
    pkgs = testPkgs;
  };
  autoUidLaunchers = import ../../config/launchd-service-launchers.nix {
    inherit lib;
    pkgs = testPkgs;
  };

  # This object defines SecItemCopyMatching itself, so the test launcher links
  # the unchanged production query code against a deterministic Keychain seam.
  fakeSecuritySource = pkgs.writeText "fake-security-framework.c" ''
    #include <CoreFoundation/CoreFoundation.h>
    #include <Security/Security.h>
    #include <dlfcn.h>
    #include <errno.h>
    #include <fcntl.h>
    #include <pthread.h>
    #include <sched.h>
    #include <signal.h>
    #include <stdatomic.h>
    #include <stdint.h>
    #include <stdlib.h>
    #include <string.h>
    #include <sys/stat.h>
    #include <unistd.h>

    extern char **environ;

    typedef pid_t (*getppid_function)(void);
    static _Atomic int simulated_parent_mode;
    static _Atomic int post_value_parent_checks;

    static const char *security_fault(void) {
        return getenv("SERVICE_TEST_SECURITY_FAULT");
    }

    static pid_t actual_parent(void) {
        static getppid_function implementation;
        if (implementation == NULL) {
            implementation = (getppid_function)dlsym(RTLD_NEXT, "getppid");
        }
        return implementation == NULL ? -1 : implementation();
    }

    pid_t getppid(void) {
        pid_t parent = actual_parent();
        int mode = atomic_load_explicit(
            &simulated_parent_mode, memory_order_acquire
        );
        if (mode == 1) return parent + 1;
        if (
            mode == 2
            && atomic_fetch_add_explicit(
                &post_value_parent_checks, 1, memory_order_acq_rel
            ) > 0
        ) {
            return parent + 1;
        }
        return parent;
    }

    static void simulate_parent_change(const char *phase) {
        const char *fault = security_fault();
        if (fault != NULL && strcmp(fault, phase) == 0) {
            atomic_store_explicit(
                &simulated_parent_mode, 1, memory_order_release
            );
        } else if (
            fault != NULL
            && strcmp(phase, "reparent-value") == 0
            && strcmp(fault, "reparent-write") == 0
        ) {
            atomic_store_explicit(
                &simulated_parent_mode, 2, memory_order_release
            );
        }
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

    static _Atomic int security_thread_ready;

    static void *hold_security_descriptor(void *unused) {
        (void)unused;
        int descriptor = open("/dev/null", O_RDONLY);
        atomic_store_explicit(
            &security_thread_ready,
            descriptor >= 0 ? 1 : -1,
            memory_order_release
        );
        for (;;) pause();
    }

    static int start_security_descriptor_thread(void) {
        pthread_t thread;
        atomic_store_explicit(&security_thread_ready, 0, memory_order_relaxed);
        if (pthread_create(&thread, NULL, hold_security_descriptor, NULL) != 0) return -1;
        if (pthread_detach(thread) != 0) return -1;
        int ready;
        do {
            sched_yield();
            ready = atomic_load_explicit(&security_thread_ready, memory_order_acquire);
        } while (ready == 0);
        return ready > 0 ? 0 : -1;
    }

    static int record_phase(const char *phase) {
        const char *log_path = getenv("SERVICE_TEST_KEYCHAIN_LOG");
        if (log_path == NULL) return -1;
        int descriptor = open(log_path, O_WRONLY | O_APPEND | O_CLOEXEC);
        if (descriptor < 0) return -1;
        int failed = write_all(
            descriptor, (const uint8_t *)phase, strlen(phase)
        ) || write_all(descriptor, (const uint8_t *)"\n", 1);
        close(descriptor);
        return failed ? -1 : 0;
    }

    static int validate_helper_descriptors(void) {
        int limit = getdtablesize();
        if (limit < 4) return -1;
        for (int descriptor = 0; descriptor < limit; ++descriptor) {
            errno = 0;
            int descriptor_flags = fcntl(descriptor, F_GETFD);
            if (descriptor_flags >= 0) {
                if (descriptor > 3) return -1;
            } else if (errno != EBADF) {
                return -1;
            }
        }

        int descriptor_flags = fcntl(3, F_GETFD);
        int status_flags = fcntl(3, F_GETFL);
        struct stat metadata;
        return descriptor_flags >= 0
            && (descriptor_flags & FD_CLOEXEC) != 0
            && status_flags >= 0
            && (status_flags & O_ACCMODE) == O_WRONLY
            && fstat(3, &metadata) == 0
            && S_ISFIFO(metadata.st_mode) ? 0 : -1;
    }

    static int validate_helper_environment(void) {
        static const char *required[] = {
            "HOME=/Users/fixture",
            "LOGNAME=fixture",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
            "USER=fixture",
        };
        static const char *allowed_additions[] = {
            "SERVICE_TEST_KEYCHAIN_DUPLICATE",
            "SERVICE_TEST_KEYCHAIN_FAIL",
            "SERVICE_TEST_KEYCHAIN_LOG",
            "SERVICE_TEST_KEYCHAIN_OPEN_SECURITY_FD",
            "SERVICE_TEST_KEYCHAIN_SIGNAL",
            "SERVICE_TEST_KEYCHAIN_VALUE_FAIL",
            "SERVICE_TEST_SECRET_FILE",
            "SERVICE_TEST_SECURITY_FAULT",
            // Darwin synthesizes this after posix_spawn from the process uid.
            "__CF_USER_TEXT_ENCODING",
        };
        int required_seen[4] = {0};
        int addition_seen[9] = {0};

        for (char **entry = environ; *entry != NULL; ++entry) {
            int matched = 0;
            for (size_t index = 0; index < 4; ++index) {
                if (strcmp(*entry, required[index]) == 0) {
                    if (required_seen[index]++) return -1;
                    matched = 1;
                    break;
                }
            }
            if (matched) continue;
            for (size_t index = 0; index < 9; ++index) {
                size_t length = strlen(allowed_additions[index]);
                if (strncmp(*entry, allowed_additions[index], length) == 0
                    && (*entry)[length] == '=') {
                    if (addition_seen[index]++) return -1;
                    matched = 1;
                    break;
                }
            }
            if (!matched) return -1;
        }
        for (size_t index = 0; index < 4; ++index) {
            if (required_seen[index] != 1) return -1;
        }
        return addition_seen[2] == 1
            && addition_seen[6] == 1
            && addition_seen[8] == 1 ? 0 : -1;
    }

    static int has_value(
        CFDictionaryRef query, const void *key, const void *expected
    ) {
        const void *value = CFDictionaryGetValue(query, key);
        return value != NULL && CFEqual(value, expected);
    }

    static CFDataRef persistent_reference(const char *value) {
        return CFDataCreate(
            kCFAllocatorDefault, (const UInt8 *)value, (CFIndex)strlen(value)
        );
    }

    static CFDataRef read_fixture_secret(void) {
        const char *secret_path = getenv("SERVICE_TEST_SECRET_FILE");
        if (secret_path == NULL) return NULL;
        int descriptor = open(secret_path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
        if (descriptor < 0) return NULL;
        struct stat metadata;
        if (fstat(descriptor, &metadata) < 0 || !S_ISREG(metadata.st_mode) || metadata.st_size > 4096) {
            close(descriptor);
            return NULL;
        }

        uint8_t bytes[4096] = {0};
        size_t used = 0;
        while (used < sizeof(bytes)) {
            ssize_t count = read(descriptor, bytes + used, sizeof(bytes) - used);
            if (count < 0) {
                if (errno == EINTR) continue;
                close(descriptor);
                memset(bytes, 0, sizeof(bytes));
                return NULL;
            }
            if (count == 0) break;
            used += (size_t)count;
        }
        close(descriptor);
        CFDataRef result = CFDataCreate(
            kCFAllocatorDefault, bytes, (CFIndex)used
        );
        memset(bytes, 0, sizeof(bytes));
        return result;
    }

    OSStatus SecCodeCopyGuestWithAttributes(
        SecCodeRef host,
        CFDictionaryRef attributes,
        SecCSFlags flags,
        SecCodeRef *guest
    ) {
        typedef OSStatus (*function_type)(
            SecCodeRef, CFDictionaryRef, SecCSFlags, SecCodeRef *
        );
        static function_type implementation;
        if (implementation == NULL) {
            implementation = (function_type)dlsym(
                RTLD_NEXT, "SecCodeCopyGuestWithAttributes"
            );
        }

        int parent_value = 0;
        CFTypeRef parent = attributes == NULL ? NULL : CFDictionaryGetValue(
            attributes, kSecGuestAttributePid
        );
        if (
            implementation == NULL
            || host != NULL
            || attributes == NULL
            || CFDictionaryGetCount(attributes) != 1
            || flags != kSecCSDefaultFlags
            || guest == NULL
            || parent == NULL
            || CFGetTypeID(parent) != CFNumberGetTypeID()
            || !CFNumberGetValue(
                (CFNumberRef)parent, kCFNumberIntType, &parent_value
            )
            || parent_value != actual_parent()
        ) {
            return errSecParam;
        }

        return implementation(host, attributes, flags, guest);
    }

    OSStatus SecCodeCheckValidity(
        SecCodeRef code,
        SecCSFlags flags,
        SecRequirementRef requirement
    ) {
        typedef OSStatus (*function_type)(
            SecCodeRef, SecCSFlags, SecRequirementRef
        );
        static function_type implementation;
        if (implementation == NULL) {
            implementation = (function_type)dlsym(
                RTLD_NEXT, "SecCodeCheckValidity"
            );
        }
        if (
            implementation == NULL
            || code == NULL
            || flags != kSecCSStrictValidate
            || requirement != NULL
        ) {
            return errSecParam;
        }
        const char *fault = security_fault();
        if (fault != NULL && strcmp(fault, "validity-failure") == 0) {
            return errSecInternalComponent;
        }
        return implementation(code, flags, requirement);
    }

    static OSStatus alter_signing_flag(
        CFDictionaryRef *information, CFStringRef key, uint32_t clear, uint32_t set
    ) {
        CFTypeRef current = CFDictionaryGetValue(*information, key);
        uint32_t value = 0;
        if (
            current == NULL
            || CFGetTypeID(current) != CFNumberGetTypeID()
            || !CFNumberGetValue(
                (CFNumberRef)current, kCFNumberSInt32Type, &value
            )
        ) {
            return errSecInternalComponent;
        }

        CFMutableDictionaryRef replacement = CFDictionaryCreateMutableCopy(
            kCFAllocatorDefault, 0, *information
        );
        value = (value & ~clear) | set;
        CFNumberRef number = CFNumberCreate(
            kCFAllocatorDefault, kCFNumberSInt32Type, &value
        );
        if (replacement == NULL || number == NULL) {
            if (replacement != NULL) CFRelease(replacement);
            if (number != NULL) CFRelease(number);
            return errSecAllocate;
        }
        CFDictionarySetValue(replacement, key, number);
        CFRelease(number);
        CFRelease(*information);
        *information = replacement;
        return errSecSuccess;
    }

    static OSStatus add_unsafe_entitlement(CFDictionaryRef *information) {
        static const uint8_t raw_byte = 1;
        CFMutableDictionaryRef replacement = CFDictionaryCreateMutableCopy(
            kCFAllocatorDefault, 0, *information
        );
        CFDataRef raw = CFDataCreate(
            kCFAllocatorDefault, &raw_byte, 1
        );
        CFMutableDictionaryRef entitlements = CFDictionaryCreateMutable(
            kCFAllocatorDefault,
            0,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks
        );
        if (replacement == NULL || raw == NULL || entitlements == NULL) {
            if (replacement != NULL) CFRelease(replacement);
            if (raw != NULL) CFRelease(raw);
            if (entitlements != NULL) CFRelease(entitlements);
            return errSecAllocate;
        }
        CFDictionarySetValue(
            entitlements,
            CFSTR("com.apple.security.get-task-allow"),
            kCFBooleanTrue
        );
        CFDictionarySetValue(
            replacement, kSecCodeInfoEntitlements, raw
        );
        CFDictionarySetValue(
            replacement, kSecCodeInfoEntitlementsDict, entitlements
        );
        CFRelease(raw);
        CFRelease(entitlements);
        CFRelease(*information);
        *information = replacement;
        return errSecSuccess;
    }

    OSStatus SecCodeCopySigningInformation(
        SecStaticCodeRef code,
        SecCSFlags flags,
        CFDictionaryRef *information
    ) {
        typedef OSStatus (*function_type)(
            SecStaticCodeRef, SecCSFlags, CFDictionaryRef *
        );
        static function_type implementation;
        if (implementation == NULL) {
            implementation = (function_type)dlsym(
                RTLD_NEXT, "SecCodeCopySigningInformation"
            );
        }
        if (
            implementation == NULL
            || flags
                != (kSecCSSigningInformation | kSecCSDynamicInformation)
        ) {
            return errSecParam;
        }

        OSStatus status = implementation(code, flags, information);
        if (status != errSecSuccess || information == NULL || *information == NULL) {
            return status;
        }

        const char *fault = security_fault();
        if (fault != NULL && strcmp(fault, "missing-runtime") == 0) {
            return alter_signing_flag(
                information, kSecCodeInfoFlags, kSecCodeSignatureRuntime, 0
            );
        }
        if (fault != NULL && strcmp(fault, "missing-library-validation") == 0) {
            return alter_signing_flag(
                information,
                kSecCodeInfoFlags,
                kSecCodeSignatureLibraryValidation,
                0
            );
        }
        if (fault != NULL && strcmp(fault, "missing-valid") == 0) {
            return alter_signing_flag(
                information, kSecCodeInfoStatus, kSecCodeStatusValid, 0
            );
        }
        if (fault != NULL && strcmp(fault, "missing-hard") == 0) {
            return alter_signing_flag(
                information, kSecCodeInfoStatus, kSecCodeStatusHard, 0
            );
        }
        if (fault != NULL && strcmp(fault, "missing-kill") == 0) {
            return alter_signing_flag(
                information, kSecCodeInfoStatus, kSecCodeStatusKill, 0
            );
        }
        if (fault != NULL && strcmp(fault, "debugged") == 0) {
            return alter_signing_flag(
                information, kSecCodeInfoStatus, 0, kSecCodeStatusDebugged
            );
        }
        if (fault != NULL && strcmp(fault, "unsafe-entitlement") == 0) {
            return add_unsafe_entitlement(information);
        }
        return status;
    }

    OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
        static int contract_checked;
        if (query == NULL || result == NULL) return errSecParam;
        *result = NULL;
        if (!contract_checked) {
            if (
                validate_helper_descriptors() != 0
                || validate_helper_environment() != 0
            ) return errSecParam;
            if (record_phase("contract") != 0) return errSecIO;
            contract_checked = 1;
        }
        if (getenv("SERVICE_TEST_KEYCHAIN_SIGNAL") != NULL) {
            if (record_phase("signal") != 0) return errSecIO;
            raise(SIGKILL);
            return errSecInternalComponent;
        }

        if (CFDictionaryContainsKey(query, kSecReturnPersistentRef)) {
            if (record_phase("match") != 0) return errSecIO;
            if (
                CFDictionaryGetCount(query) != 6
                || !has_value(query, kSecClass, kSecClassGenericPassword)
                || !has_value(query, kSecAttrAccount, CFSTR("fixture"))
                || !has_value(
                    query, kSecAttrService, CFSTR("nix-config.vlc-telnet-fixture")
                )
                || !has_value(query, kSecReturnPersistentRef, kCFBooleanTrue)
                || !has_value(query, kSecMatchLimit, kSecMatchLimitAll)
                || !has_value(
                    query, kSecUseAuthenticationUI, kSecUseAuthenticationUISkip
                )
            ) return errSecParam;
            if (getenv("SERVICE_TEST_KEYCHAIN_FAIL") != NULL) {
                return errSecItemNotFound;
            }
            CFDataRef first = persistent_reference("fixture-one");
            CFDataRef second = persistent_reference("fixture-two");
            if (first == NULL || second == NULL) {
                if (first != NULL) CFRelease(first);
                if (second != NULL) CFRelease(second);
                return errSecAllocate;
            }
            const void *matches[] = { first, second };
            CFIndex count = getenv("SERVICE_TEST_KEYCHAIN_DUPLICATE") == NULL ? 1 : 2;
            *result = CFArrayCreate(
                kCFAllocatorDefault, matches, count, &kCFTypeArrayCallBacks
            );
            CFRelease(first);
            CFRelease(second);
            if (*result != NULL) simulate_parent_change("reparent-match");
            return *result == NULL ? errSecAllocate : errSecSuccess;
        }

        if (CFDictionaryContainsKey(query, kSecValuePersistentRef)) {
            if (record_phase("value") != 0) return errSecIO;
            CFDataRef expected = persistent_reference("fixture-one");
            int valid = expected != NULL
                && CFDictionaryGetCount(query) == 3
                && has_value(query, kSecValuePersistentRef, expected)
                && has_value(query, kSecReturnData, kCFBooleanTrue)
                && has_value(
                    query, kSecUseAuthenticationUI, kSecUseAuthenticationUISkip
                );
            if (expected != NULL) CFRelease(expected);
            if (!valid) return errSecParam;
            if (getenv("SERVICE_TEST_KEYCHAIN_VALUE_FAIL") != NULL) {
                return errSecInteractionNotAllowed;
            }
            *result = read_fixture_secret();
            if (
                *result != NULL
                && getenv("SERVICE_TEST_KEYCHAIN_OPEN_SECURITY_FD") != NULL
                && start_security_descriptor_thread() != 0
            ) {
                CFRelease(*result);
                *result = NULL;
                return errSecIO;
            }
            if (*result != NULL) simulate_parent_change("reparent-value");
            return *result == NULL ? errSecIO : errSecSuccess;
        }

        return errSecParam;
    }
  '';

  fakeEntitlementSecuritySource = pkgs.writeText "fake-entitlement-security.c" ''
    #include <CoreFoundation/CoreFoundation.h>
    #include <Security/Security.h>
    #include <dlfcn.h>
    #include <stdint.h>
    #include <stdlib.h>
    #include <string.h>

    OSStatus SecCodeCopySigningInformation(
        SecStaticCodeRef code,
        SecCSFlags flags,
        CFDictionaryRef *information
    ) {
        typedef OSStatus (*function_type)(
            SecStaticCodeRef, SecCSFlags, CFDictionaryRef *
        );
        static function_type implementation;
        if (implementation == NULL) {
            implementation = (function_type)dlsym(
                RTLD_NEXT, "SecCodeCopySigningInformation"
            );
        }
        const char *mode = getenv("SERVICE_TEST_ENTITLEMENT_MODE");
        if (implementation == NULL || information == NULL) return errSecParam;
        if (mode != NULL && strcmp(mode, "error") == 0) {
            *information = NULL;
            return errSecInternalComponent;
        }

        OSStatus status = implementation(code, flags, information);
        if (
            status != errSecSuccess
            || *information == NULL
            || mode == NULL
        ) {
            return status;
        }

        static const uint8_t raw_byte = 1;
        CFMutableDictionaryRef replacement = CFDictionaryCreateMutableCopy(
            kCFAllocatorDefault, 0, *information
        );
        CFDataRef raw = CFDataCreate(
            kCFAllocatorDefault, &raw_byte, 1
        );
        if (replacement == NULL || raw == NULL) {
            if (replacement != NULL) CFRelease(replacement);
            if (raw != NULL) CFRelease(raw);
            return errSecAllocate;
        }

        CFDictionarySetValue(replacement, kSecCodeInfoEntitlements, raw);
        CFRelease(raw);
        if (strcmp(mode, "raw-only") == 0) {
            CFDictionaryRemoveValue(
                replacement, kSecCodeInfoEntitlementsDict
            );
        } else if (strcmp(mode, "non-dictionary") == 0) {
            CFArrayRef parsed = CFArrayCreate(
                kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks
            );
            if (parsed == NULL) {
                CFRelease(replacement);
                return errSecAllocate;
            }
            CFDictionarySetValue(
                replacement, kSecCodeInfoEntitlementsDict, parsed
            );
            CFRelease(parsed);
        } else if (strcmp(mode, "unsafe") == 0) {
            CFMutableDictionaryRef parsed = CFDictionaryCreateMutable(
                kCFAllocatorDefault,
                0,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks
            );
            if (parsed == NULL) {
                CFRelease(replacement);
                return errSecAllocate;
            }
            CFDictionarySetValue(
                parsed,
                CFSTR("com.apple.security.cs.disable-library-validation"),
                kCFBooleanTrue
            );
            CFDictionarySetValue(
                replacement, kSecCodeInfoEntitlementsDict, parsed
            );
            CFRelease(parsed);
        } else {
            CFRelease(replacement);
            return errSecParam;
        }

        CFRelease(*information);
        *information = replacement;
        return errSecSuccess;
    }
  '';

  # libproc reports syscall failure as zero bytes with errno set. Interpose
  # that exact contract so the launcher must fail before consulting Keychain.
  fakeProcPidinfoFailureSource = pkgs.writeText "fake-proc-pidinfo-failure.c" ''
    #include <errno.h>
    #include <stdint.h>
    #include <sys/proc_info.h>

    int proc_pidinfo(
        int pid, int flavor, uint64_t arg, void *buffer, int buffersize
    ) {
        (void)pid;
        (void)arg;
        if (
            flavor == PROC_PIDLISTTHREADS
            && buffer != NULL
            && buffersize >= (int)PROC_PIDLISTTHREADS_SIZE
        ) {
            *(uint64_t *)buffer = 1;
            errno = 0;
            return (int)PROC_PIDLISTTHREADS_SIZE;
        }
        errno = EIO;
        return 0;
    }
  '';

  fakeHistoricalThreadSource = pkgs.writeText "fake-historical-thread.c" ''
    #include <pthread.h>
    #include <unistd.h>

    static void *finish_thread(void *unused) {
        (void)unused;
        return NULL;
    }

    __attribute__((constructor))
    static void establish_thread_history(void) {
        pthread_t thread;
        if (
            pthread_create(&thread, NULL, finish_thread, NULL) != 0
            || pthread_join(thread, NULL) != 0
        ) _exit(125);
    }
  '';

  fakeLiveThreadSource = pkgs.writeText "fake-live-thread.c" ''
    #include <pthread.h>
    #include <sched.h>
    #include <stdatomic.h>
    #include <unistd.h>

    static _Atomic int thread_ready;

    static void *hold_thread(void *unused) {
        (void)unused;
        atomic_store_explicit(&thread_ready, 1, memory_order_release);
        for (;;) pause();
    }

    __attribute__((constructor))
    static void establish_live_thread(void) {
        pthread_t thread;
        if (
            pthread_create(&thread, NULL, hold_thread, NULL) != 0
            || pthread_detach(thread) != 0
        ) _exit(125);
        while (!atomic_load_explicit(&thread_ready, memory_order_acquire)) {
            sched_yield();
        }
    }
  '';

  fakePostHelperThreadSource = pkgs.writeText "fake-post-helper-thread.c" ''
    #define _DARWIN_C_SOURCE 1
    #include <errno.h>
    #include <pthread.h>
    #include <sched.h>
    #include <stdatomic.h>
    #include <stdlib.h>
    #include <sys/resource.h>
    #include <sys/wait.h>
    #include <unistd.h>

    static _Atomic int thread_ready;

    static void *hold_thread(void *unused) {
        (void)unused;
        atomic_store_explicit(&thread_ready, 1, memory_order_release);
        for (;;) pause();
    }

    static int start_thread(void) {
        pthread_t thread;
        if (
            pthread_create(&thread, NULL, hold_thread, NULL) != 0
            || pthread_detach(thread) != 0
        ) {
            return -1;
        }
        while (!atomic_load_explicit(&thread_ready, memory_order_acquire)) {
            sched_yield();
        }
        return 0;
    }

    pid_t waitpid(pid_t pid, int *status, int options) {
        pid_t result = wait4(pid, status, options, NULL);
        int saved_errno = errno;
        if (
            result == pid
            && status != NULL
            && WIFEXITED(*status)
            && WEXITSTATUS(*status) == EXIT_SUCCESS
            && start_thread() != 0
        ) {
            _exit(125);
        }
        errno = saved_errno;
        return result;
    }
  '';

  fakeFinalThreadSource = pkgs.writeText "fake-final-thread.c" ''
    #define _DARWIN_C_SOURCE 1
    #include <dlfcn.h>
    #include <errno.h>
    #include <pthread.h>
    #include <sched.h>
    #include <stdatomic.h>
    #include <stdint.h>
    #include <sys/proc_info.h>
    #include <unistd.h>

    typedef int (*proc_pidinfo_function)(
        int, int, uint64_t, void *, int
    );
    static _Atomic int thread_ready;
    static int thread_queries;

    static void *hold_thread(void *unused) {
        (void)unused;
        atomic_store_explicit(&thread_ready, 1, memory_order_release);
        for (;;) pause();
    }

    static int start_thread(void) {
        pthread_t thread;
        if (
            pthread_create(&thread, NULL, hold_thread, NULL) != 0
            || pthread_detach(thread) != 0
        ) {
            return -1;
        }
        while (!atomic_load_explicit(&thread_ready, memory_order_acquire)) {
            sched_yield();
        }
        return 0;
    }

    int proc_pidinfo(
        int pid, int flavor, uint64_t arg, void *buffer, int buffersize
    ) {
        static proc_pidinfo_function implementation;
        if (implementation == NULL) {
            implementation = (proc_pidinfo_function)dlsym(
                RTLD_NEXT, "proc_pidinfo"
            );
        }
        if (implementation == NULL) {
            errno = ENOSYS;
            return -1;
        }

        int result = implementation(pid, flavor, arg, buffer, buffersize);
        int saved_errno = errno;
        if (
            pid == getpid()
            && flavor == PROC_PIDLISTTHREADS
            && result == PROC_PIDLISTTHREADS_SIZE
            && ++thread_queries == 2
            && start_thread() != 0
        ) {
            _exit(125);
        }
        errno = saved_errno;
        return result;
    }
  '';

  fakeDyldInjectionSource = pkgs.writeText "fake-dyld-injection.c" ''
    #include <fcntl.h>
    #include <stdlib.h>
    #include <unistd.h>

    __attribute__((constructor))
    static void record_injection(void) {
        const char *marker = getenv("SERVICE_TEST_DYLD_MARKER");
        if (marker == NULL) return;
        int descriptor = open(marker, O_WRONLY | O_CREAT | O_EXCL, 0600);
        if (descriptor < 0) return;
        (void)write(descriptor, "injected\n", 9);
        close(descriptor);
    }
  '';
  fakeDyldHostSource = pkgs.writeText "fake-dyld-host.c" ''
    int main(void) { return 0; }
  '';
  fakeDyldInjection = pkgs.runCommandCC "fake-dyld-injection" { } ''
    mkdir -p "$out/bin" "$out/lib"
    "$CC" -std=c11 -Wall -Wextra -Werror -dynamiclib \
      ${fakeDyldInjectionSource} -o "$out/lib/injection.dylib"
    "$CC" -std=c11 -Wall -Wextra -Werror \
      ${fakeDyldHostSource} -o "$out/bin/host"
  '';

  fakeVlc = pkgs.writeTextFile {
    name = "fake-vlc";
    destination = "/bin/fake-vlc";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      import hashlib
      import json
      import os
      import pathlib
      import stat
      import sys

      def open_fds():
          result = []
          for entry in os.listdir("/dev/fd"):
              if not entry.isdecimal():
                  continue
              descriptor = int(entry)
              try:
                  os.fstat(descriptor)
              except OSError:
                  continue
              result.append(descriptor)
          return sorted(result)

      arguments = sys.argv[1:]
      inherited_fds = open_fds()
      config_paths = [
          argument.removeprefix("--config=")
          for argument in arguments
          if argument.startswith("--config=")
      ]
      if len(config_paths) != 1:
          raise SystemExit("fake-vlc: expected exactly one config descriptor")

      # Model VLC 3's parser: it consumes three bytes while looking for a UTF-8 BOM
      # and seeks back only when the BOM is absent. Seeking a pipe must fail.
      config_metadata = os.fstat(3)
      with open(config_paths[0], "rb", buffering=0) as config:
          prefix = config.read(3)
          if prefix != b"\xef\xbb\xbf":
              config.seek(0)
          body = config.read()

      if not body:
          raise SystemExit("fake-vlc: empty telnet config")
      # VLC 3's line parser unconditionally replaces the final byte returned by
      # getline with NUL. A missing line feed must therefore drop the last
      # password byte here rather than being accepted by a friendlier fixture.
      body = body[:-1]
      key = b"telnet-password="
      if not body.startswith(key) or b"\n" in body or b"\r" in body:
          raise SystemExit("fake-vlc: invalid telnet config")
      password = body[len(key):]
      password.decode("utf-8")
      user_lua = (
          pathlib.Path(os.environ["HOME"])
          / "Library/Application Support/org.videolan.vlc/lua/intf/telnet.lua"
      )
      # Darwin's Python startup adds these two process-local values. Remove only
      # those interpreter additions so this field remains the execve environment.
      environment = dict(os.environ)
      environment.pop("LC_CTYPE", None)
      environment.pop("__CF_USER_TEXT_ENCODING", None)
      record = {
          "argv": sys.argv,
          "config_is_fifo": stat.S_ISFIFO(config_metadata.st_mode),
          "environment": dict(sorted(environment.items())),
          "open_fds": inherited_fds,
          "password_sha256": hashlib.sha256(password).hexdigest(),
          "pid": os.getpid(),
          "user_lua_exists": user_lua.exists(),
      }
      print(json.dumps(record, separators=(",", ":")), flush=True)
    '';
  };
  fakeVlcHome = pkgs.runCommand "fake-vlc-home" { } ''
    mkdir -p "$out/Library/Application Support/org.videolan.vlc"
  '';
  hashVlcFixture = pkgs.writeText "hash-vlc-fixture.py" ''
    import base64
    import hashlib
    import os
    import pathlib
    import stat
    import sys

    bundle = pathlib.Path(sys.argv[1])
    digest = hashlib.sha256()
    entries = sorted(
        bundle.rglob("*"),
        key=lambda path: os.fsencode(path.relative_to(bundle).as_posix()),
    )
    for path in entries:
        relative = os.fsencode(path.relative_to(bundle).as_posix())
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode):
            kind = b"L"
            mode = 0o777
            value = os.fsencode(os.readlink(path))
        elif stat.S_ISDIR(metadata.st_mode):
            kind = b"D"
            mode = 0o555
            value = b""
        elif stat.S_ISREG(metadata.st_mode):
            kind = b"F"
            mode = 0o555 if metadata.st_mode & stat.S_IXUSR else 0o444
            value = hashlib.sha256(path.read_bytes()).digest()
        else:
            raise AssertionError(path)
        digest.update(kind)
        digest.update(mode.to_bytes(2, "big"))
        for field in (relative, value):
            digest.update(len(field).to_bytes(8, "big"))
            digest.update(field)
    print("sha256-" + base64.b64encode(digest.digest()).decode("ascii"))
  '';
  fakeVlcCodesign = pkgs.writeTextFile {
    name = "fake-vlc-codesign";
    destination = "/bin/codesign";
    executable = true;
    text = ''
      #!${pkgs.runtimeShell}
      set -eu

      state_directory=$(pwd -P)
      log="$state_directory/vlc-verifier.jsonl"
      mode_file="$state_directory/vlc-verifier-mode"
      IFS= read -r mode <"$mode_file"
      [ -n "$mode" ] || exit 9
      [ "''${BASH_ENV-}" != "$state_directory/hostile-bash-env" ] || exit 9
      [ "''${PATH-}" != /hostile-verifier-path ] || exit 9
      [ "''${PYTHONHOME-}" != /hostile-python-home ] || exit 9
      [ "''${PYTHONPATH-}" != /hostile-python-path ] || exit 9
      [ "''${CODESIGN_ALLOCATE-}" != /hostile-codesign-allocate ] || exit 9
      [ "''${DYLD_INSERT_LIBRARIES-}" != /hostile-insert-library ] || exit 9
      [ "''${DYLD_LIBRARY_PATH-}" != /hostile-library-path ] || exit 9
      separator=
      target=
      for argument in "$@"; do
        printf '%s%s' "$separator" "$argument" >>"$log"
        separator=$(printf '\t')
        target=$argument
      done
      printf '\n' >>"$log"

      case " $* " in
        *' --verify '*)
          [ "$mode" != verify-failure ] || exit 9
          exit 0
          ;;
        *' --entitlements '*)
          [ "$mode" != entitlements-failure ] || exit 9
          case "$mode" in
            invalid-entitlements)
              printf '%s\n' 'not a property list'
              ;;
            whitespace-entitlements)
              printf ' \t\n'
              ;;
            array-entitlements)
              printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><array/></plist>'
              ;;
            unsafe-allow-dyld)
              printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>com.apple.security.cs.allow-dyld-environment-variables</key><true/></dict></plist>'
              ;;
            unsafe-apple-get-task)
              printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>com.apple.security.get-task-allow</key><true/></dict></plist>'
              ;;
            unsafe-plain-get-task)
              printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>get-task-allow</key><true/></dict></plist>'
              ;;
            unsafe-suffix-get-task)
              printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>example.get-task-allow</key><true/></dict></plist>'
              ;;
            unsafe-nested-entitlement)
              case "$target" in
                */Contents/MacOS/plugins/libtospdif_plugin.dylib)
                  printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>com.apple.security.cs.allow-dyld-environment-variables</key><true/></dict></plist>'
                  ;;
              esac
              ;;
            safe-entitlements)
              printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>com.apple.security.cs.disable-library-validation</key><true/></dict></plist>'
              ;;
          esac
          exit 0
          ;;
        *' --verbose=6 '*)
          [ "$mode" != display-failure ] || exit 9
          [ "$mode" != empty-display ] || exit 0
          if [ "$mode" = malformed-display ]; then
            printf '%s\n' 'malformed successful display' >&2
            exit 0
          fi
          flags=0x10000\(runtime\)
          case "$mode" in
            no-runtime) flags=0x0\(\) ;;
            truncated-runtime) flags=0x10000\(runtime ;;
            misleading-runtime) flags=0x0\(runtime\) ;;
            numeric-runtime-only) flags=0x10000\(\) ;;
            leading-comma-runtime) flags=0x10000\(,runtime\) ;;
            trailing-comma-runtime) flags=0x10000\(runtime,\) ;;
            doubled-comma-runtime) flags=0x10000\(runtime,,adhoc\) ;;
            invalid-atom-runtime) flags=0x10000\(runtime,-\) ;;
            duplicate-label-runtime) flags=0x10000\(runtime,runtime\) ;;
            duplicate-record-runtime)
              printf '%s\n' \
                'CodeDirectory v=20500 size=924 flags=0x10000(runtime) hashes=18+7 location=embedded' \
                'CodeDirectory v=20500 size=924 flags=0x10000(runtime) hashes=18+7 location=embedded' >&2
              exit 0
              ;;
          esac
          printf 'CodeDirectory v=20500 size=924 flags=%s hashes=18+7 location=embedded\n' "$flags" >&2
          exit 0
          ;;
      esac
      echo 'fake-vlc-codesign: unexpected invocation' >&2
      exit 9
    '';
  };

  assertDockerLogProgram = pkgs.writeText "assert-docker-log.py" ''
    import json
    import os
    import pathlib
    import sys

    mode, log, data_directory = sys.argv[1:]
    image = "mcr.microsoft.com/mssql/server:2022-latest"
    image_id = "sha256:" + "a" * 64
    probe = (
        'data=/var/opt/mssql; probe="$data/.nix-config-bind-probe.$$"; '
        'test -d "$data" && test -r "$data" && test -w "$data" '
        '&& test -x "$data" && (set -C; : >"$probe") && rm -f "$probe"'
    )
    calls = [
        ["info"],
        ["pull", image],
        ["image", "inspect", "--format", "{{.Id}}", image],
        [
            "run", "--pull=never", "--rm",
            "--mount", f"type=bind,source={data_directory},target=/var/opt/mssql",
            "--entrypoint", "/bin/sh",
            image_id,
            "-c", probe,
        ],
        [
            "container", "ls", "--all", "--filter", "name=^/mssql-server$",
            "--format", "{{.Names}}",
        ],
        ["rm", "-f", "mssql-server"],
        [
            "run", "--pull=never", "-d",
            "--name", "mssql-server",
            "--restart", "unless-stopped",
            "--publish", "127.0.0.1:1433:1433/tcp",
            "--mount", f"type=bind,source={data_directory},target=/var/opt/mssql",
            "--env", "ACCEPT_EULA=Y",
            "--env-file", "/dev/fd/3",
            image_id,
        ],
    ]
    if mode == "info-retry":
        calls = [calls[0], *calls]
    elif mode == "pull-swap":
        calls = calls[:3]
    elif mode == "image-invalid":
        calls = calls[:3]
    elif mode in ("mount-failure", "mount-swap"):
        calls = calls[:4]
    elif mode in (
        "rm-failure",
        "rm-swap",
        "rm-credential-mutation",
        "rm-credential-content-mutation",
        "rm-credential-mode-mutation",
        "rm-credential-acl-mutation",
    ):
        calls = calls[:6]
    elif mode == "container-absent":
        calls = [*calls[:5], calls[-1]]
    elif mode == "container-ambiguous":
        calls = calls[:5]
    elif mode != "success":
        raise AssertionError(mode)
    records = [json.loads(line) for line in pathlib.Path(log).read_text().splitlines()]
    assert [record["argv"] for record in records] == calls, records
    assert all(record["secret_value_env_keys"] == [] for record in records), records
    expected_environment = {
        "DOCKER_CONFIG": "/var/root/.docker",
        "DOCKER_HOST": "unix:///var/run/docker.sock",
        "HOME": "/var/root",
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    }
    assert all(record["environment"] == expected_environment for record in records), records
    expected_fds = [[0, 1, 2] for _ in records]
    if mode in ("success", "info-retry", "container-absent"):
        expected_fds[-1] = [0, 1, 2, 3]
    assert [record["open_fds"] for record in records] == expected_fds, records
    assert [record["env_file_access_mode"] for record in records] == (
        [None] * (len(records) - 1) + [os.O_RDONLY]
        if mode in ("success", "info-retry", "container-absent")
        else [None] * len(records)
    ), records
    assert [record["env_file_matches_fixture"] for record in records] == (
        [None] * (len(records) - 1) + [True]
        if mode in ("success", "info-retry", "container-absent")
        else [None] * len(records)
    ), records
    assert [record["env_file_is_configured_object"] for record in records] == (
        [None] * (len(records) - 1) + [True]
        if mode in ("success", "info-retry", "container-absent")
        else [None] * len(records)
    ), records
  '';
  assertValidatorLogProgram = pkgs.writeText "assert-validator-log.py" ''
    import json
    import pathlib
    import sys

    (
        log,
        credential_directory,
        data_directory,
        parent_owner_uid,
        data_owner_uid,
        validator,
        *rest,
    ) = sys.argv[1:]
    mode = rest[0] if rest else "success"
    records = [json.loads(line) for line in pathlib.Path(log).read_text().splitlines()]
    path_arguments = [
        "-I", validator,
        credential_directory,
        str(pathlib.Path(credential_directory).parents[1]),
        parent_owner_uid,
        data_directory,
        str(pathlib.Path(data_directory).parents[1]),
        parent_owner_uid,
        data_owner_uid,
    ]
    credential_arguments = [
        "-I", validator, "--credential-fd", "3", parent_owner_uid,
        credential_directory, str(pathlib.Path(credential_directory).parents[1]),
    ]
    expected = []
    docker_call_counts = [0, 3, 4, 4, 6, 6]
    if mode == "info-retry":
        docker_call_counts = [0, 4, 5, 5, 7, 7]
    elif mode != "success":
        raise AssertionError(mode)
    for docker_calls, phase, descriptors in [
        (docker_call_counts[0], "paths", [0, 1, 2]),
        (docker_call_counts[1], "paths", [0, 1, 2]),
        (docker_call_counts[2], "paths", [0, 1, 2]),
        (docker_call_counts[3], "credential", [0, 1, 2, 3]),
        (docker_call_counts[4], "paths", [0, 1, 2]),
        (docker_call_counts[5], "credential", [0, 1, 2, 3]),
    ]:
        expected.append({
            "argv": credential_arguments if phase == "credential" else path_arguments,
            "docker_calls": docker_calls,
            "environment": {},
            "open_fds": descriptors,
            "phase": phase,
        })
    assert records == expected, records
  '';
  assertVlcLogProgram = pkgs.writeText "assert-vlc-log.py" ''
    import hashlib
    import json
    import pathlib
    import sys

    keychain_path, output_path, secret_path, pid_arg, fds_arg = sys.argv[1:]
    keychain = pathlib.Path(keychain_path).read_text().splitlines()
    vlc = [json.loads(line) for line in pathlib.Path(output_path).read_text().splitlines()]
    assert len(vlc) == 1, vlc
    expected_pid = int(pid_arg) if pid_arg != "-" else vlc[0]["pid"]
    expected_fds = [int(descriptor) for descriptor in fds_arg.split(",")]
    assert isinstance(expected_pid, int) and expected_pid > 0, expected_pid
    assert keychain == ["contract", "match", "value"], keychain
    assert vlc == [{
        "argv": [
            ${builtins.toJSON "${fakeVlc}/bin/fake-vlc"},
            "-I", "telnet",
            "--no-ignore-config",
            "--config=/dev/fd/3",
            "--telnet-host=127.0.0.1",
            "--telnet-port=4212",
        ],
        "config_is_fifo": True,
        "environment": {
            "HOME": ${builtins.toJSON "${fakeVlcHome}"},
            "LOGNAME": "fixture",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "USER": "fixture",
        },
        "open_fds": expected_fds,
        "password_sha256": hashlib.sha256(
            pathlib.Path(secret_path).read_bytes()
        ).hexdigest(),
        "pid": expected_pid,
        "user_lua_exists": False,
    }], vlc
  '';
  assertSecretAbsentProgram = pkgs.writeText "assert-secret-absent.py" ''
    import argparse
    import base64
    import pathlib

    parser = argparse.ArgumentParser()
    parser.add_argument("--assignments", action="store_true")
    parser.add_argument("--opaque-binary", action="store_true")
    parser.add_argument("--verify-short-fragments", action="store_true")
    parser.add_argument("secret_file", type=pathlib.Path)
    parser.add_argument("artifacts", nargs="*", type=pathlib.Path)
    options = parser.parse_args()

    secret_file = options.secret_file.read_bytes()
    if options.assignments:
        secrets = {
            line.split(b"=", 1)[1]
            for line in secret_file.splitlines()
            if b"=" in line and line.split(b"=", 1)[1]
        }
    else:
        secrets = {secret_file} if secret_file else set()
    raw_variants = set(secrets)
    for secret in secrets:
        if len(secret) >= 8:
            raw_variants.update(
                secret[index:index + 8] for index in range(len(secret) - 7)
            )
    encoded_variants = set()
    unpadded_encoded_variants = set()
    for value in raw_variants:
        standard = base64.b64encode(value)
        urlsafe = base64.urlsafe_b64encode(value)
        encoded_variants.update({
            value.hex().encode(),
            value.hex().upper().encode(),
            standard,
            urlsafe,
        })
        unpadded_encoded_variants.update({
            (standard.rstrip(b"="), standard),
            (urlsafe.rstrip(b"="), urlsafe),
        })
    substring_variants = raw_variants | encoded_variants

    # Short fragments are only safe to match when the actual synthetic
    # credential embeds a distinctive high-byte canary. Empty and ordinary
    # credentials retain full-value, encoded-value, and eight-byte-window
    # coverage.
    short_canaries = {
        secret[:7]
        for secret in secrets
        if len(secret) >= 7 and all(byte >= 0x80 for byte in secret[:7])
    }
    short_raw_variants = {
        canary[start:stop]
        for canary in short_canaries
        for start in range(len(canary))
        for stop in range(start + 1, len(canary) + 1)
    }
    short_encoded_variants = set()
    for value in short_raw_variants:
        short_encoded_variants.update({
            value.hex().encode(),
            value.hex().upper().encode(),
            base64.b64encode(value),
            base64.b64encode(value).rstrip(b"="),
            base64.urlsafe_b64encode(value),
            base64.urlsafe_b64encode(value).rstrip(b"="),
        })

    encoded_left_token_bytes = frozenset(
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/_-"
    )
    encoded_right_token_bytes = encoded_left_token_bytes | {ord("=")}

    def contains_bounded(haystack, needle):
        offset = 0
        while True:
            index = haystack.find(needle, offset)
            if index < 0:
                return False
            end = index + len(needle)
            if (
                (index == 0 or haystack[index - 1] not in encoded_left_token_bytes)
                and (
                    end == len(haystack)
                    or haystack[end] not in encoded_right_token_bytes
                )
            ):
                return True
            offset = index + 1

    def contains_unpadded_encoding(haystack, needle, padded):
        offset = 0
        while True:
            index = haystack.find(needle, offset)
            if index < 0:
                return False
            # The padded branch owns only the exact padded occurrence. Any
            # other suffix retains the original substring-match behavior.
            if not haystack.startswith(padded, index):
                return True
            offset = index + 1

    def contains_secret(artifact):
        if any(value and value in artifact for value in substring_variants):
            return True
        if any(
            contains_unpadded_encoding(artifact, unpadded, padded)
            for unpadded, padded in unpadded_encoded_variants
        ):
            return True
        if options.opaque_binary:
            return False
        return any(value in artifact for value in short_raw_variants) or any(
            contains_bounded(artifact, value)
            for value in short_encoded_variants
        )

    if options.opaque_binary and options.verify_short_fragments:
        raise SystemExit("opaque binaries do not support short-fragment verification")
    if options.verify_short_fragments:
        if not short_canaries:
            raise SystemExit(
                "short-fragment verification requires an embedded high-byte canary"
            )
        for fragment in short_raw_variants:
            probes = (
                b"raw=[" + fragment + b"]",
                b"HEX=" + fragment.hex().encode() + b"\n",
                b"HEX=" + fragment.hex().upper().encode() + b"\n",
                b"B64=" + base64.b64encode(fragment) + b"\n",
                b"B64=" + base64.b64encode(fragment).rstrip(b"=") + b"\n",
                b"B64=" + base64.urlsafe_b64encode(fragment) + b"\n",
                b"B64=" + base64.urlsafe_b64encode(fragment).rstrip(b"=") + b"\n",
            )
            if not all(contains_secret(probe) for probe in probes):
                raise SystemExit("short-fragment detector missed a probe")
        if any(
            contains_bounded(b"prefix" + value + b"suffix", value)
            for value in short_encoded_variants
        ):
            raise SystemExit("short-fragment detector matched an embedded token")

    for artifact_path in options.artifacts:
        artifact = artifact_path.read_bytes()
        if contains_secret(artifact):
            raise SystemExit(f"secret material entered {artifact_path}")
  '';
  shortLeakMutantProgram = pkgs.writeText "short-leak-mutant.py" ''
    import argparse
    import base64
    import pathlib

    parser = argparse.ArgumentParser()
    parser.add_argument("--assignments", action="store_true")
    parser.add_argument("encoding", choices=("raw", "hex", "base64", "base64url"))
    parser.add_argument("offset", type=int, choices=range(7))
    parser.add_argument("length", type=int, choices=range(1, 8))
    parser.add_argument("secret_file", type=pathlib.Path)
    parser.add_argument("artifact", type=pathlib.Path)
    options = parser.parse_args()

    secret_file = options.secret_file.read_bytes()
    if options.assignments:
        secrets = [
            line.split(b"=", 1)[1]
            for line in secret_file.splitlines()
            if b"=" in line and line.split(b"=", 1)[1]
        ]
    else:
        secrets = [secret_file] if secret_file else []
    if len(secrets) != 1:
        raise SystemExit("leak mutant requires exactly one secret")
    canary = secrets[0][:7]
    if len(canary) != 7 or any(byte < 0x80 for byte in canary):
        raise SystemExit("leak mutant requires an embedded high-byte canary")
    encoded_fragments = (
        (
            base64.b64encode(canary[offset:offset + length]),
            base64.urlsafe_b64encode(canary[offset:offset + length]),
        )
        for offset in range(len(canary))
        for length in range(1, len(canary) - offset + 1)
    )
    if not any(
        standard != urlsafe
        and (b"+" in standard or b"/" in standard)
        and (b"-" in urlsafe or b"_" in urlsafe)
        for standard, urlsafe in encoded_fragments
    ):
        raise SystemExit("canary does not distinguish base64url from base64")
    if options.offset + options.length > len(canary):
        raise SystemExit("leak mutant fragment exceeds the high-byte canary")

    fragment = canary[options.offset:options.offset + options.length]
    encoders = {
        "raw": lambda value: value,
        "hex": lambda value: value.hex().encode(),
        "base64": base64.b64encode,
        "base64url": base64.urlsafe_b64encode,
    }
    options.artifact.write_bytes(
        b"mutant=[" + encoders[options.encoding](fragment) + b"]\n"
    )
  '';
  snapshotTreeProgram = pkgs.writeText "snapshot-tree.py" ''
    import hashlib
    import json
    import os
    import pathlib
    import stat
    import sys

    records = []
    for argument in sys.argv[1:]:
        root = pathlib.Path(argument)
        paths = [root]
        if stat.S_ISDIR(root.lstat().st_mode):
            for directory, names, files in os.walk(root, followlinks=False):
                names.sort()
                base = pathlib.Path(directory)
                paths.extend(base / name for name in sorted(names + files))
        for path in paths:
            metadata = path.lstat()
            record = {
                "path": str(path.relative_to(root.parent)),
                "device": metadata.st_dev,
                "inode": metadata.st_ino,
                "uid": metadata.st_uid,
                "gid": metadata.st_gid,
                "mode": stat.S_IFMT(metadata.st_mode) | stat.S_IMODE(metadata.st_mode),
                "links": metadata.st_nlink,
                "size": metadata.st_size,
                "ctime_ns": metadata.st_ctime_ns,
                "mtime_ns": metadata.st_mtime_ns,
            }
            if stat.S_ISREG(metadata.st_mode):
                record["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
            elif stat.S_ISLNK(metadata.st_mode):
                record["target"] = os.readlink(path)
            records.append(record)
    print(json.dumps(records, sort_keys=True, separators=(",", ":")))
  '';

  testMssqlLauncher =
    launcherSet: overrides:
    launcherSet.mssql (
      {
        credentialDirectory = "/__SERVICE_TEST_ROOT__/nix-config/mssql";
        credentialOwnerUid = "__SERVICE_TEST_UID__";
        credentialTrustRoot = "/__SERVICE_TEST_ROOT__";
        dataDirectory = "/__SERVICE_TEST_ROOT__/mssql-data/data";
        dataOwner = "fixture";
        dataOwnerUid = "__SERVICE_TEST_DATA_UID__";
        dataParentOwnerUid = "__SERVICE_TEST_UID__";
        dataTrustRoot = "/__SERVICE_TEST_ROOT__";
      }
      // overrides
    );
  mssqlLauncher = testMssqlLauncher launchers { };
  mssqlWrongCredentialOwnerLauncher = testMssqlLauncher launchers {
    credentialOwnerUid = "__SERVICE_TEST_WRONG_UID__";
  };
  mssqlWrongDataOwnerLauncher = testMssqlLauncher launchers {
    dataOwnerUid = "__SERVICE_TEST_WRONG_UID__";
  };
  mssqlWrongDataParentOwnerLauncher = testMssqlLauncher launchers {
    dataParentOwnerUid = "__SERVICE_TEST_WRONG_UID__";
  };
  mssqlSwappedDataOwnersLauncher = testMssqlLauncher launchers {
    dataOwnerUid = "__SERVICE_TEST_UID__";
    dataParentOwnerUid = "__SERVICE_TEST_DATA_UID__";
  };
  mssqlAutoDataOwnerLauncher = testMssqlLauncher autoUidLaunchers {
    dataOwnerUid = null;
  };
  invalidMssqlPath =
    path:
    builtins.tryEval (
      launchers.mssql {
        credentialDirectory = path;
        dataDirectory = "/valid/data";
        dataOwner = "fixture";
      }
    );
  invalidMssqlDataPath =
    path:
    builtins.tryEval (
      launchers.mssql {
        credentialDirectory = "/valid/credentials";
        dataDirectory = path;
        dataOwner = "fixture";
      }
    );
  vlcLauncher = launchers.vlcTelnet {
    account = "fixture";
    home = "/Users/fixture";
    keychainService = "nix-config.vlc-telnet-fixture";
    securityFixtureSource = fakeSecuritySource;
    vlcBin = "${fakeVlc}/bin/fake-vlc";
    vlcHome = "${fakeVlcHome}";
  };
  vlcProcPidinfoFailureLauncher = launchers.vlcTelnet {
    account = "fixture";
    home = "/Users/fixture";
    keychainService = "nix-config.vlc-telnet-fixture";
    launcherFixtureSource = fakeProcPidinfoFailureSource;
    securityFixtureSource = fakeSecuritySource;
    vlcBin = "${fakeVlc}/bin/fake-vlc";
    vlcHome = "${fakeVlcHome}";
  };
  vlcHistoricalThreadLauncher = launchers.vlcTelnet {
    account = "fixture";
    home = "/Users/fixture";
    keychainService = "nix-config.vlc-telnet-fixture";
    launcherFixtureSource = fakeHistoricalThreadSource;
    securityFixtureSource = fakeSecuritySource;
    vlcBin = "${fakeVlc}/bin/fake-vlc";
    vlcHome = "${fakeVlcHome}";
  };
  vlcLiveThreadLauncher = launchers.vlcTelnet {
    account = "fixture";
    home = "/Users/fixture";
    keychainService = "nix-config.vlc-telnet-fixture";
    launcherFixtureSource = fakeLiveThreadSource;
    securityFixtureSource = fakeSecuritySource;
    vlcBin = "${fakeVlc}/bin/fake-vlc";
    vlcHome = "${fakeVlcHome}";
  };
  vlcPostHelperThreadLauncher = launchers.vlcTelnet {
    account = "fixture";
    home = "/Users/fixture";
    keychainService = "nix-config.vlc-telnet-fixture";
    launcherFixtureSource = fakePostHelperThreadSource;
    securityFixtureSource = fakeSecuritySource;
    vlcBin = "${fakeVlc}/bin/fake-vlc";
    vlcHome = "${fakeVlcHome}";
  };
  vlcFinalThreadLauncher = launchers.vlcTelnet {
    account = "fixture";
    home = "/Users/fixture";
    keychainService = "nix-config.vlc-telnet-fixture";
    launcherFixtureSource = fakeFinalThreadSource;
    securityFixtureSource = fakeSecuritySource;
    vlcBin = "${fakeVlc}/bin/fake-vlc";
    vlcHome = "${fakeVlcHome}";
  };
  invalidVlcPath =
    overrides:
    builtins.tryEval (
      launchers.vlcTelnet (
        {
          account = "fixture";
          home = "/Users/fixture";
          vlcBin = "${fakeVlc}/bin/fake-vlc";
          vlcHome = "${fakeVlcHome}";
        }
        // overrides
      )
    );
  invalidVlcPort =
    port:
    builtins.tryEval (
      launchers.vlcTelnet {
        account = "fixture";
        home = "/Users/fixture";
        inherit port;
        vlcBin = "${fakeVlc}/bin/fake-vlc";
        vlcHome = "${fakeVlcHome}";
      }
    );

  toolsDocument = builtins.fromJSON (builtins.readFile ../../sources/tools.json);
  vlcCatalog = toolsDocument.sources.vlc;
  vlcCatalogUrl = "https://get.videolan.org/vlc/3.0.23/macosx/vlc-3.0.23-arm64.dmg";
  vlcCatalogHash = "sha256-/G+sCNh/U4UX1ErKDF56JEtnyMTLWJv0eDY6cxX9Xg0=";
  vlcBundleTreeHash = "sha256-cCXSUXZTLCG1OYKOgOMRwq5sd9GTImCCrGQBGLa5ah8=";
  securityDocument = builtins.readFile ../../doc/SECURITY.md;
  darwinPkgs = darwinConfigurations.hera.pkgs;
  productionLaunchers = import ../../config/launchd-service-launchers.nix {
    inherit lib;
    pkgs = darwinPkgs;
  };
  expectedMssql = productionLaunchers.mssql {
    credentialDirectory = "/Library/Application Support/nix-config/mssql";
    credentialOwnerUid = 0;
    credentialTrustRoot = "/";
    dataDirectory = "/private/var/lib/nix-config/mssql-data/data";
    dataOwner = "johnw";
    dataOwnerUid = null;
    dataParentOwnerUid = 0;
    dataTrustRoot = "/";
  };
  expectedVlcApp = darwinPkgs.callPackage ../../packages/vlc-bin.nix { };
  expectedVlcVerifier = expectedVlcApp.mkVerifier {
    codesign = "${fakeVlcCodesign}/bin/codesign";
  };
  expectedVlcHome = darwinPkgs.runCommand "vlc-telnet-home" { } ''
    mkdir -p "$out/Library/Application Support/org.videolan.vlc"
  '';
  expectedVlc = productionLaunchers.vlcTelnet {
    account = "johnw";
    home = "/Users/johnw";
    keychainService = "nix-config.vlc-telnet";
    port = 4212;
    vlcBin = "${expectedVlcApp}/Applications/VLC.app/Contents/MacOS/VLC";
    vlcHome = "${expectedVlcHome}";
  };
  entitlementValidatorFixture = pkgs.runCommandCC "vlc-entitlement-validator-fixture" { } ''
    mkdir -p "$out/bin"
    "$CC" -std=c11 -Wall -Wextra -Werror \
      ${expectedVlc.entitlementValidatorSource} \
      ${fakeEntitlementSecuritySource} \
      -framework CoreFoundation -framework Security \
      -o "$out/bin/validate-vlc-entitlements"
  '';
  hera = darwinConfigurations.hera.config;
  clio = darwinConfigurations.clio.config;
in
assert toolsDocument.schemaVersion == 1;
assert vlcCatalog.version == "3.0.23";
assert vlcCatalog.source.fetcher == "fetchurl";
assert vlcCatalog.source.url == vlcCatalogUrl;
assert
  vlcCatalog.source.args == {
    hash = vlcCatalogHash;
    url = vlcCatalogUrl;
  };
assert vlcCatalog.hashes == { bundleTreeHash = vlcBundleTreeHash; };
assert vlcCatalog.update.kind == "url-release";
assert vlcCatalog.update.policy == "manual";
assert lib.hasInfix "pinned as part of the VLC credential-consumer boundary"
  vlcCatalog.update.reason;
assert lib.hasInfix "pinned VLC 3.0.23 executable" securityDocument;
assert lib.hasInfix
  "official arm64 DMG and the complete xattr-free application tree are independently hash-pinned"
  securityDocument;
assert lib.hasInfix
  "tree pin includes every relative path, entry type, symlink target, file content, and Nix-canonical permission mode"
  securityDocument;
assert lib.hasInfix "package verifies the complete tree hash, rejects fat Mach-O code"
  securityDocument;
assert lib.hasInfix
  "external Apple-anchor and exact VideoLAN team requirement to the bundle and every retained thin Mach-O object while also checking each signature's designated requirement"
  securityDocument;
assert lib.hasInfix "parsed Info.plist, a consistent Hardened Runtime bit and label"
  securityDocument;
assert lib.hasInfix "successful entitlement inspection for every signature" securityDocument;
assert lib.hasInfix "Successful empty entitlement output is treated as absence" securityDocument;
assert lib.hasInfix
  "every nonempty result must parse as a property-list dictionary before dyld-environment and task-debugging grants are rejected"
  securityDocument;
assert lib.hasInfix
  "verifier enters through Apple's environment-clearing utility before the fixed Nix Python interpreter starts"
  securityDocument;
assert lib.hasInfix
  "exactly one `generic-password` Keychain item with service `nix-config.vlc-telnet` and account `johnw`"
  securityDocument;
assert lib.hasInfix "zero or duplicate matches fail closed" securityDocument;
assert lib.hasInfix "without placing it on any command argv" securityDocument;
assert lib.hasInfix "never automate Keychain ACL changes" securityDocument;
assert lib.hasInfix "must not be the exact one-byte value `0x04`" securityDocument;
assert lib.hasInfix
  "must not begin or end with space, horizontal tab (`0x09`), vertical tab (`0x0b`), or form feed (`0x0c`)"
  securityDocument;
assert expectedVlcApp.doInstallCheck;
assert
  hera.launchd.daemons.mssql-server.serviceConfig.ProgramArguments == [
    "${expectedMssql}/bin/mssql-server-launcher"
  ];
assert
  hera.launchd.daemons.mssql-server.serviceConfig.EnvironmentVariables == {
    DOCKER_CONFIG = "/var/root/.docker";
    DOCKER_HOST = "unix:///var/run/docker.sock";
    HOME = "/var/root";
    LOGNAME = "root";
    PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
    USER = "root";
    ZDOTDIR = "/var/root";
  };
assert
  clio.launchd.daemons.mssql-server.serviceConfig.ProgramArguments == [
    "${expectedMssql}/bin/mssql-server-launcher"
  ];
assert
  clio.launchd.daemons.mssql-server.serviceConfig.EnvironmentVariables == {
    DOCKER_CONFIG = "/var/root/.docker";
    DOCKER_HOST = "unix:///var/run/docker.sock";
    HOME = "/var/root";
    LOGNAME = "root";
    PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
    USER = "root";
    ZDOTDIR = "/var/root";
  };
assert
  hera.launchd.user.agents.vlc-telnet.serviceConfig.ProgramArguments == [
    "${expectedVlc}/bin/vlc-telnet-launcher"
  ];
assert
  hera.launchd.user.agents.vlc-telnet.serviceConfig.EnvironmentVariables == {
    HOME = "/Users/johnw";
    LOGNAME = "johnw";
    PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
    USER = "johnw";
  };
assert hera.launchd.user.agents.vlc-telnet.serviceConfig.ThrottleInterval == 30;
assert !(clio.launchd.user.agents ? vlc-telnet);
assert !(invalidMssqlPath "relative/path").success;
assert !(invalidMssqlPath "/path/with/../credentials").success;
assert !(invalidMssqlPath "/path/with/./credentials").success;
assert !(invalidMssqlPath "/path/with/trailing/").success;
assert !(invalidMssqlDataPath "/data//leaf").success;
assert !(invalidMssqlDataPath "/data/with,comma").success;
assert !(invalidVlcPort 0).success;
assert !(invalidVlcPort 65536).success;
assert !(invalidVlcPort "4212").success;
assert !(invalidVlcPath { vlcBin = "/usr/bin/vlc"; }).success;
assert !(invalidVlcPath { vlcBin = "relative/vlc"; }).success;
assert !(invalidVlcPath { vlcBin = "${fakeVlc}/./bin/fake-vlc"; }).success;
assert !(invalidVlcPath { vlcBin = "${fakeVlc}/bin/"; }).success;
assert !(invalidVlcPath { vlcHome = "/tmp/vlc-home"; }).success;
assert !(invalidVlcPath { vlcHome = "relative/vlc-home"; }).success;
assert !(invalidVlcPath { vlcHome = "${fakeVlcHome}/./state"; }).success;
assert !(invalidVlcPath { vlcHome = "${fakeVlcHome}/"; }).success;
pkgs.runCommand "service-credential-boundaries" { } ''
  set -eu

  fail() {
    echo "service-credentials: $*" >&2
    exit 1
  }

  snapshot_tree() {
    ${pkgs.python3}/bin/python3 ${snapshotTreeProgram} "$@"
  }

  record_mssql_secret() {
    if [ -f "$credential_file" ]; then
      cp "$credential_file" "$mssql_secret_oracle"
    fi
  }

  scan_mssql_artifacts() {
    label=$1
    ${pkgs.python3}/bin/python3 ${assertSecretAbsentProgram} \
      --assignments \
      "$mssql_secret_oracle" \
      "$label.out" "$label.err" "$SERVICE_TEST_DOCKER_LOG" \
      "$SERVICE_TEST_VALIDATOR_LOG"
  }

  scan_vlc_artifacts() {
    ${pkgs.python3}/bin/python3 ${assertSecretAbsentProgram} \
      "$SERVICE_TEST_SECRET_FILE" "$@"
  }

  assert_short_fragment_mutants_rejected_with() {
    scanner=$1
    mode=$2
    secret_file=$3
    label=$4
    shift 4
    scanner_mode=
    [ "$mode" != assignments ] || scanner_mode=--assignments
    artifact_index=0
    for artifact in "$@"; do
      clean_artifact="$artifact.clean"
      cp "$artifact" "$clean_artifact"
      offset=0
      while [ "$offset" -lt 7 ]; do
        length=1
        while [ "$length" -le $((7 - offset)) ]; do
          for encoding in raw hex base64 base64url; do
            result="$label-mutant-$artifact_index-$encoding-$offset-$length"
            ${pkgs.python3}/bin/python3 ${shortLeakMutantProgram} \
              $scanner_mode "$encoding" "$offset" "$length" \
              "$secret_file" "$artifact"
            if ${pkgs.python3}/bin/python3 "$scanner" \
              $scanner_mode "$secret_file" "$@" \
              >"$result.out" 2>"$result.err"; then
              cp "$clean_artifact" "$artifact"
              rm "$clean_artifact" "$result.out" "$result.err"
              fail "the $label scanner accepted a $length-byte $encoding leak mutant at offset $offset"
            fi
            grep -F "secret material entered $artifact" "$result.err" >/dev/null ||
              fail "the $label scanner rejected a leak mutant for the wrong reason"
            cp "$clean_artifact" "$artifact"
            rm "$result.out" "$result.err"
          done
          length=$((length + 1))
        done
        offset=$((offset + 1))
      done
      rm "$clean_artifact"
      artifact_index=$((artifact_index + 1))
    done
  }

  assert_short_fragment_mutants_rejected() {
    assert_short_fragment_mutants_rejected_with \
      ${assertSecretAbsentProgram} "$@"
  }

  expect_mssql_reject() {
    label=$1
    record_mssql_secret
    trust_tree_before=$(snapshot_tree "$trust_root")
    : >"$SERVICE_TEST_DOCKER_LOG"
    : >"$SERVICE_TEST_VALIDATOR_LOG"
    if "$mssql_command" >"$label.out" 2>"$label.err"; then
      fail "MSSQL accepted $label"
    fi
    scan_mssql_artifacts "$label"
    [ ! -s "$SERVICE_TEST_DOCKER_LOG" ] ||
      fail "MSSQL ran Docker after rejecting $label"
    [ "$(snapshot_tree "$trust_root")" = "$trust_tree_before" ] ||
      fail "MSSQL mutated the managed tree while rejecting $label"
  }

  expect_mssql_accept() {
    label=$1
    mode=''${2:-success}
    record_mssql_secret
    : >"$SERVICE_TEST_DOCKER_LOG"
    : >"$SERVICE_TEST_VALIDATOR_LOG"
    managed_metadata_before=$(snapshot_tree "$trust_root")
    "$mssql_command" 19<"$TMPDIR/fd-sentinel" \
      >"$label.out" 2>"$label.err" ||
      fail "MSSQL rejected $label"
    [ "$(snapshot_tree "$trust_root")" = "$managed_metadata_before" ] ||
      fail "MSSQL mutated the managed tree while accepting $label"
    scan_mssql_artifacts "$label"
    ${pkgs.python3}/bin/python3 ${assertDockerLogProgram} \
      "$mode" "$SERVICE_TEST_DOCKER_LOG" "$data_directory"
    ${pkgs.python3}/bin/python3 ${assertValidatorLogProgram} \
      "$SERVICE_TEST_VALIDATOR_LOG" "$credential_directory" \
      "$data_directory" "$fixture_uid" "$data_uid" \
      ${mssqlLauncher.mssqlPathValidator} "$mode"
  }

  expect_vlc_reject() {
    label=$1
    source_marker=$2
    launcher_marker=$3
    expected_phases=$4
    : >"$SERVICE_TEST_KEYCHAIN_LOG"
    status=0
    ${pkgs.coreutils}/bin/timeout 5 \
      ${vlcLauncher}/bin/vlc-telnet-launcher \
      >"$label.out" 2>"$label.err" || status=$?
    [ "$status" -ne 0 ] || fail "VLC accepted $label"
    [ "$status" -ne 124 ] || fail "VLC hung while rejecting $label"
    [ ! -s "$label.out" ] || fail "VLC ran after rejecting $label"
    if [ "$source_marker" != - ]; then
      grep -F "$source_marker" "$label.err" >/dev/null ||
        fail "$label missed its source marker"
    fi
    grep -F "$launcher_marker" "$label.err" >/dev/null ||
      fail "$label missed its launcher marker"
    actual_phases=$(paste -sd, "$SERVICE_TEST_KEYCHAIN_LOG")
    [ "$expected_phases" != - ] || expected_phases=
    [ "$actual_phases" = "$expected_phases" ] ||
      fail "$label crossed the wrong Keychain query layers"
    scan_vlc_artifacts \
      "$label.out" "$label.err" "$SERVICE_TEST_KEYCHAIN_LOG"
  }

  expect_vlc_thread_reject() {
    label=$1
    launcher=$2
    expected_marker=$3
    expected_phases=$4
    : >"$SERVICE_TEST_KEYCHAIN_LOG"
    status=0
    ${pkgs.coreutils}/bin/timeout 5 "$launcher" \
      >"$label.out" 2>"$label.err" || status=$?
    [ "$status" -ne 0 ] || fail "VLC accepted $label"
    [ "$status" -ne 124 ] || fail "VLC hung while rejecting $label"
    grep -F "$expected_marker" "$label.err" >/dev/null ||
      fail "$label missed its rejection marker"
    [ ! -s "$label.out" ] || fail "$label executed VLC"
    actual_phases=$(paste -sd, "$SERVICE_TEST_KEYCHAIN_LOG")
    [ "$expected_phases" != - ] || expected_phases=
    [ "$actual_phases" = "$expected_phases" ] ||
      fail "$label crossed the wrong Keychain query layers"
    scan_vlc_artifacts \
      "$label.out" "$label.err" "$SERVICE_TEST_KEYCHAIN_LOG"
  }

  assert_vlc_accept() {
    label=$1
    expected_pid=$2
    expected_fds=$3
    [ ! -s "$label.err" ] || fail "$label wrote an unexpected diagnostic"
    ${pkgs.python3}/bin/python3 ${assertVlcLogProgram} \
      "$SERVICE_TEST_KEYCHAIN_LOG" "$label.out" \
      "$SERVICE_TEST_SECRET_FILE" "$expected_pid" "$expected_fds"
    scan_vlc_artifacts \
      "$label.out" "$label.err" "$SERVICE_TEST_KEYCHAIN_LOG"
  }

  run_vlc_accept() {
    label=$1
    : >"$SERVICE_TEST_KEYCHAIN_LOG"
    if ! ${pkgs.coreutils}/bin/timeout 5 \
      ${vlcLauncher}/bin/vlc-telnet-launcher \
      >"$label.out" 2>"$label.err"; then
      fail "VLC rejected $label"
    fi
    assert_vlc_accept "$label" - 0,1,2,3
  }

  cd "$TMPDIR"
  export SERVICE_TEST_DOCKER_LOG="$TMPDIR/docker.jsonl"
  export SERVICE_TEST_VALIDATOR_LOG="$TMPDIR/validator.jsonl"
  export SERVICE_TEST_KEYCHAIN_LOG="$TMPDIR/keychain.jsonl"
  SERVICE_TEST_SECRET_FILE="$TMPDIR/keychain-secret"

  trust_root="$TMPDIR/service-trust"
  credential_directory="$trust_root/nix-config/mssql"
  credential_file="$credential_directory/environment"
  data_parent="$trust_root/mssql-data"
  data_directory="$data_parent/data"
  mssql_secret_oracle="$TMPDIR/mssql-secret-oracle"
  mkdir -m 0700 "$trust_root"
  mkdir -m 0700 "$trust_root/nix-config"
  mkdir -m 0700 "$credential_directory"
  mkdir -m 0700 "$data_parent"
  mkdir -m 0700 "$data_directory"

  fixture_uid=$(id -u)
  wrong_uid=$((fixture_uid + 1))
  data_uid=$((fixture_uid + 2))
  prepare_mssql_launcher() {
    source=$1
    destination=$2
    cp "$source" "$destination"
    if grep -F __SERVICE_TEST_WRONG_UID__ "$destination" >/dev/null; then
      substituteInPlace "$destination" \
        --replace-fail __SERVICE_TEST_WRONG_UID__ "$wrong_uid"
    fi
    if grep -F __SERVICE_TEST_DATA_UID__ "$destination" >/dev/null; then
      substituteInPlace "$destination" \
        --replace-fail __SERVICE_TEST_DATA_UID__ "$data_uid"
    fi
    substituteInPlace "$destination" \
      --replace-fail /__SERVICE_TEST_ROOT__ "$trust_root" \
      --replace-fail __SERVICE_TEST_UID__ "$fixture_uid"
  }
  mssql_command="$TMPDIR/mssql-server-launcher"
  mssql_wrong_credential_owner="$TMPDIR/mssql-wrong-credential-owner"
  mssql_wrong_data_owner="$TMPDIR/mssql-wrong-data-owner"
  mssql_wrong_data_parent_owner="$TMPDIR/mssql-wrong-data-parent-owner"
  mssql_swapped_data_owners="$TMPDIR/mssql-swapped-data-owners"
  mssql_auto_data_owner="$TMPDIR/mssql-auto-data-owner"
  prepare_mssql_launcher \
    ${mssqlLauncher}/bin/mssql-server-launcher "$mssql_command"
  prepare_mssql_launcher \
    ${mssqlWrongCredentialOwnerLauncher}/bin/mssql-server-launcher \
    "$mssql_wrong_credential_owner"
  prepare_mssql_launcher \
    ${mssqlWrongDataOwnerLauncher}/bin/mssql-server-launcher \
    "$mssql_wrong_data_owner"
  prepare_mssql_launcher \
    ${mssqlWrongDataParentOwnerLauncher}/bin/mssql-server-launcher \
    "$mssql_wrong_data_parent_owner"
  prepare_mssql_launcher \
    ${mssqlSwappedDataOwnersLauncher}/bin/mssql-server-launcher \
    "$mssql_swapped_data_owners"
  prepare_mssql_launcher \
    ${mssqlAutoDataOwnerLauncher}/bin/mssql-server-launcher \
    "$mssql_auto_data_owner"

  mssql_secret=$(printf '\364\217\277\275\363\240\200\201Aa1!mssql-runtime-sentinel')
  printf 'MSSQL_SA_PASSWORD=%s\n' "$mssql_secret" >"$credential_file"
  chmod 0600 "$credential_file"
  cp "$credential_file" "$mssql_secret_oracle"
  ${pkgs.python3}/bin/python3 ${assertSecretAbsentProgram} \
    --assignments --verify-short-fragments "$mssql_secret_oracle"
  : >"$SERVICE_TEST_DOCKER_LOG"
  : >"$SERVICE_TEST_VALIDATOR_LOG"
  initial_managed_metadata_before=$(snapshot_tree "$trust_root")
  printf 'this inherited descriptor must be replaced' >"$TMPDIR/fd-sentinel"

  "$mssql_command" 3<"$TMPDIR/fd-sentinel" 19<"$TMPDIR/fd-sentinel" \
    >initial-mssql.out 2>initial-mssql.err
  scan_mssql_artifacts initial-mssql
  [ "$(snapshot_tree "$trust_root")" = "$initial_managed_metadata_before" ] ||
    fail "MSSQL mutated its managed tree during a successful launch"
  [ -e validator-data-owner-observed ] ||
    fail "the MSSQL fixture did not model the distinct data-leaf owner"
  ${pkgs.python3}/bin/python3 ${assertDockerLogProgram} \
    success "$SERVICE_TEST_DOCKER_LOG" "$data_directory"
  ${pkgs.python3}/bin/python3 ${assertValidatorLogProgram} \
    "$SERVICE_TEST_VALIDATOR_LOG" "$credential_directory" \
    "$data_directory" "$fixture_uid" "$data_uid" \
    ${mssqlLauncher.mssqlPathValidator}
  if grep -F "$mssql_secret" "$SERVICE_TEST_DOCKER_LOG" \
    "$mssql_command" >/dev/null; then
    fail "MSSQL credential entered argv, environment evidence, or the launcher"
  fi

  record_mssql_secret
  : >"$SERVICE_TEST_DOCKER_LOG"
  : >"$SERVICE_TEST_VALIDATOR_LOG"
  poisoned_managed_metadata_before=$(snapshot_tree "$trust_root")
  DOCKER_HOST=tcp://attacker.invalid:2375 \
    DOCKER_CONTEXT=attacker \
    DOCKER_TLS_VERIFY=1 \
    DOCKER_CERT_PATH="$TMPDIR/untrusted-docker-certificates" \
    MSSQL_SA_PASSWORD="$mssql_secret" \
    POISON_VALUE="$mssql_secret" \
    "$mssql_command" 19<"$TMPDIR/fd-sentinel" \
    >poisoned-environment.out 2>poisoned-environment.err ||
    fail "MSSQL rejected a sanitized caller environment"
  [ "$(snapshot_tree "$trust_root")" = "$poisoned_managed_metadata_before" ] ||
    fail "MSSQL mutated its managed tree under a poisoned caller environment"
  scan_mssql_artifacts poisoned-environment
  ${pkgs.python3}/bin/python3 ${assertDockerLogProgram} \
    success "$SERVICE_TEST_DOCKER_LOG" "$data_directory"
  ${pkgs.python3}/bin/python3 ${assertValidatorLogProgram} \
    "$SERVICE_TEST_VALIDATOR_LOG" "$credential_directory" \
    "$data_directory" "$fixture_uid" "$data_uid" \
    ${mssqlLauncher.mssqlPathValidator}

  grep -F "docker=${darwinPkgs.docker-client}/bin/docker" \
    ${expectedMssql}/bin/mssql-server-launcher >/dev/null ||
    fail "production MSSQL does not use the Nix Docker client"
  [ "$(grep -c '/bin/python3 -I ' ${expectedMssql}/bin/mssql-server-launcher)" -eq 2 ] ||
    fail "production MSSQL validators do not use isolated Python"
  if grep -F '/usr/local/bin/docker' ${expectedMssql}/bin/mssql-server-launcher >/dev/null; then
    fail "production MSSQL retained the mutable Docker.app client path"
  fi
  grep -F 'DOCKER_HOST=unix:///var/run/docker.sock' \
    ${expectedMssql}/bin/mssql-server-launcher >/dev/null ||
    fail "production MSSQL does not pin the local Docker endpoint"
  grep -F 'char *const sanitized_environment[] = { NULL };' \
    ${expectedMssql.descriptorSanitizerSource} >/dev/null ||
    fail "production child execution does not construct an empty environment"
  grep -F 'execve(argv[2], &argv[2], sanitized_environment)' \
    ${expectedMssql.descriptorSanitizerSource} >/dev/null ||
    fail "production child execution does not apply its empty environment"
  if grep -F -- '--volume' ${expectedMssql}/bin/mssql-server-launcher >/dev/null; then
    fail "production MSSQL retained Docker's auto-creating volume syntax"
  fi
  grep -F 'data_owner=johnw' ${expectedMssql}/bin/mssql-server-launcher >/dev/null ||
    fail "production MSSQL lost the user-owned data leaf"
  grep -F 'data_parent_owner_uid=0' \
    ${expectedMssql}/bin/mssql-server-launcher >/dev/null ||
    fail "production MSSQL data parents are not root-owned"
  ${pkgs.python3}/bin/python3 - ${expectedMssql}/bin/mssql-server-launcher <<'PY'
  import pathlib
  import sys
  source = pathlib.Path(sys.argv[1]).read_text()
  assert "data_owner_uid=" + chr(39) * 2 in source
  PY

  rm -f id.json
  mssql_command="$mssql_auto_data_owner"
  expect_mssql_accept automatic-data-owner-uid
  ${pkgs.python3}/bin/python3 - id.json <<'PY'
  import json
  import pathlib
  import sys
  record = json.loads(pathlib.Path(sys.argv[1]).read_text())
  assert record == {
      "argv": ["-u", "--", "fixture"],
      "environment": {},
      "open_fds": [0, 1, 2],
  }, record
  PY

  ownership_metadata_before=$(snapshot_tree "$trust_root")
  mssql_command="$mssql_wrong_credential_owner"
  expect_mssql_reject wrong-credential-owner-uid
  [ "$(snapshot_tree "$trust_root")" = "$ownership_metadata_before" ] ||
    fail "MSSQL repaired the credential ownership mismatch"
  mssql_command="$TMPDIR/mssql-server-launcher"
  rm -f validator-credential-intermediate-owner-observed
  touch validator-wrong-credential-intermediate-owner
  expect_mssql_reject wrong-credential-intermediate-owner-uid
  rm validator-wrong-credential-intermediate-owner
  [ -e validator-credential-intermediate-owner-observed ] ||
    fail "the credential intermediate-owner fixture did not reach its path"
  grep -F "managed directory must be owned by uid $fixture_uid" \
    wrong-credential-intermediate-owner-uid.err >/dev/null ||
    fail "MSSQL did not reject the credential intermediate's owner"
  rm validator-credential-intermediate-owner-observed
  rm -f validator-credential-file-owner-observed
  touch validator-wrong-credential-file-owner
  expect_mssql_reject wrong-credential-file-owner-uid
  rm validator-wrong-credential-file-owner
  [ -e validator-credential-file-owner-observed ] ||
    fail "the credential-file owner fixture did not reach the regular file"
  grep -F 'credential file must be singly linked, owner-only, and mode 600' \
    wrong-credential-file-owner-uid.err >/dev/null ||
    fail "MSSQL did not reject the credential file's independent owner"
  [ "$(snapshot_tree "$trust_root")" = "$ownership_metadata_before" ] ||
    fail "MSSQL mutated the tree around a credential-file owner mismatch"
  mssql_command="$mssql_wrong_data_owner"
  expect_mssql_reject wrong-data-owner-uid
  [ "$(snapshot_tree "$trust_root")" = "$ownership_metadata_before" ] ||
    fail "MSSQL repaired the data ownership mismatch"
  mssql_command="$mssql_wrong_data_parent_owner"
  expect_mssql_reject wrong-data-parent-owner-uid
  [ "$(snapshot_tree "$trust_root")" = "$ownership_metadata_before" ] ||
    fail "MSSQL repaired the data-parent ownership mismatch"
  mssql_command="$TMPDIR/mssql-server-launcher"
  rm -f validator-data-intermediate-owner-observed
  touch validator-wrong-data-intermediate-owner
  expect_mssql_reject wrong-data-intermediate-owner-uid
  rm validator-wrong-data-intermediate-owner
  [ -e validator-data-intermediate-owner-observed ] ||
    fail "the data intermediate-owner fixture did not reach its path"
  grep -F "managed directory must be owned by uid $fixture_uid" \
    wrong-data-intermediate-owner-uid.err >/dev/null ||
    fail "MSSQL did not reject the data intermediate's owner"
  rm validator-data-intermediate-owner-observed
  mssql_command="$mssql_swapped_data_owners"
  expect_mssql_reject swapped-data-owner-uids
  [ "$(snapshot_tree "$trust_root")" = "$ownership_metadata_before" ] ||
    fail "MSSQL mutated the tree around swapped data owner arguments"
  mssql_command="$TMPDIR/mssql-server-launcher"

  mv "$credential_file" "$credential_directory/missing-environment"
  missing_credential_metadata=$(snapshot_tree "$trust_root")
  expect_mssql_reject missing-credential-file
  [ ! -e "$credential_file" ] || fail "MSSQL created a missing credential file"
  [ "$(snapshot_tree "$trust_root")" = "$missing_credential_metadata" ] ||
    fail "MSSQL mutated the tree around a missing credential file"
  mv "$credential_directory/missing-environment" "$credential_file"

  mv "$data_directory" "$data_parent/missing-data"
  missing_data_metadata=$(snapshot_tree "$trust_root")
  expect_mssql_reject missing-data-directory
  [ ! -e "$data_directory" ] || fail "MSSQL created a missing data directory"
  [ "$(snapshot_tree "$trust_root")" = "$missing_data_metadata" ] ||
    fail "MSSQL mutated the tree around a missing data directory"
  mv "$data_parent/missing-data" "$data_directory"

  mv "$trust_root/nix-config" "$trust_root/missing-nix-config"
  missing_credential_ancestor_metadata=$(snapshot_tree "$trust_root")
  expect_mssql_reject missing-credential-ancestor
  [ ! -e "$trust_root/nix-config" ] ||
    fail "MSSQL created a missing credential ancestor"
  [ "$(snapshot_tree "$trust_root")" = "$missing_credential_ancestor_metadata" ] ||
    fail "MSSQL mutated the tree around a missing credential ancestor"
  mv "$trust_root/missing-nix-config" "$trust_root/nix-config"

  mv "$data_parent" "$trust_root/missing-mssql-data"
  missing_data_ancestor_metadata=$(snapshot_tree "$trust_root")
  expect_mssql_reject missing-data-ancestor
  [ ! -e "$data_parent" ] || fail "MSSQL created a missing data ancestor"
  [ "$(snapshot_tree "$trust_root")" = "$missing_data_ancestor_metadata" ] ||
    fail "MSSQL mutated the tree around a missing data ancestor"
  mv "$trust_root/missing-mssql-data" "$data_parent"

  vlc_verifier_bundle=${expectedVlcApp}/Applications/VLC.app
  vlc_verifier_log="$PWD/vlc-verifier.jsonl"
  vlc_verifier_mode="$PWD/vlc-verifier-mode"
  hostile_bash_env="$PWD/hostile-bash-env"
  printf '%s\n' 'exit 88' >"$hostile_bash_env"
  printf '%s\n' success >"$vlc_verifier_mode"
  : >"$vlc_verifier_log"
  ${pkgs.python3}/bin/python3 -I - \
    ${expectedVlcVerifier} ${darwinPkgs.python3}/bin/python3 <<'PY'
  import pathlib
  import sys

  first_line = pathlib.Path(sys.argv[1]).read_bytes().splitlines()[0]
  expected = f"#!/usr/bin/env -S -i {sys.argv[2]} -I".encode("ascii")
  assert first_line == expected, (first_line, expected)
  PY
  BASH_ENV="$hostile_bash_env" PATH=/hostile-verifier-path \
    PYTHONHOME=/hostile-python-home PYTHONPATH=/hostile-python-path \
    CODESIGN_ALLOCATE=/hostile-codesign-allocate \
    DYLD_INSERT_LIBRARIES=/hostile-insert-library \
    DYLD_LIBRARY_PATH=/hostile-library-path \
    ${expectedVlcVerifier} "$vlc_verifier_bundle" \
    >vlc-verifier-success.out 2>vlc-verifier-success.err ||
    fail "the VLC package verifier rejected its pinned bundle fixture"
  [ ! -s vlc-verifier-success.out ] ||
    fail "the VLC package verifier wrote unexpected output"
  [ ! -s vlc-verifier-success.err ] ||
    fail "the VLC package verifier wrote unexpected diagnostics"
  ${pkgs.python3}/bin/python3 - "$vlc_verifier_log" "$vlc_verifier_bundle" <<'PY'
  import os
  import pathlib
  import sys

  log_path, bundle = sys.argv[1:]
  records = [line.split("\t") for line in pathlib.Path(log_path).read_text().splitlines()]
  bundle_requirement = (
      'anchor apple generic and identifier "org.videolan.vlc" and '
      'certificate leaf[subject.OU] = "75GAHG3SZQ"'
  )
  team_requirement = (
      'anchor apple generic and certificate leaf[subject.OU] = "75GAHG3SZQ"'
  )
  verifications = [record for record in records if "--verify" in record]
  entitlements = [record for record in records if "--entitlements" in record]
  displays = [record for record in records if "--verbose=6" in record]
  bundle_path = pathlib.Path(bundle)
  thin_magics = {
      b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",
      b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
  }
  fat_magics = {
      b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
      b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
  }
  expected_code_paths = []
  for path in sorted(
      bundle_path.rglob("*"),
      key=lambda item: os.fsencode(item.relative_to(bundle_path).as_posix()),
  ):
      if not path.is_file() or path.is_symlink():
          continue
      with path.open("rb") as stream:
          magic = stream.read(4)
      assert magic not in fat_magics, path
      if magic in thin_magics:
          expected_code_paths.append(str(path))
  assert verifications[0] == [
      "--verify", "--verbose=1", "--strict", "--ignore-resources",
      "-R", "=" + bundle_requirement, bundle,
  ], verifications[0]
  actual_code_paths = [record[-1] for record in verifications[1:]]
  assert actual_code_paths == expected_code_paths, (
      actual_code_paths, expected_code_paths
  )
  assert len(actual_code_paths) == len(set(actual_code_paths)), actual_code_paths
  assert len(actual_code_paths) > 300, len(actual_code_paths)
  assert all(
      record == [
          "--verify", "--verbose=1", "--strict", "--ignore-resources",
          "-R", "=" + team_requirement, record[-1],
      ]
      for record in verifications[1:]
  ), verifications
  assert len(entitlements) == len(verifications), (
      len(entitlements), len(verifications)
  )
  assert all(
      record[:-1] == ["--display", "--entitlements", "-", "--xml"]
      for record in entitlements
  ), entitlements
  assert [record[-1] for record in entitlements] == [
      bundle, *expected_code_paths
  ], entitlements
  assert displays == [["--display", "--verbose=6", bundle]], displays
  assert len(records) == 2 * len(verifications) + 1, len(records)
  PY

  printf '%s\n' safe-entitlements >"$vlc_verifier_mode"
  : >"$vlc_verifier_log"
  ${expectedVlcVerifier} "$vlc_verifier_bundle" \
    >vlc-verifier-safe-entitlements.out \
    2>vlc-verifier-safe-entitlements.err ||
    fail "the VLC package verifier rejected benign nonempty entitlements"

  expect_vlc_verifier_reject() {
    mode=$1
    printf '%s\n' "$mode" >"$vlc_verifier_mode"
    : >"$vlc_verifier_log"
    if ${expectedVlcVerifier} "$vlc_verifier_bundle" \
      >"vlc-verifier-$mode.out" 2>"vlc-verifier-$mode.err"; then
      fail "the VLC package verifier accepted hostile $mode inspection"
    fi
    [ ! -s "vlc-verifier-$mode.out" ] ||
      fail "the VLC package verifier exposed output during $mode inspection"
    grep -F 'VLC bundle verification failed:' \
      "vlc-verifier-$mode.err" >/dev/null ||
      fail "the VLC package verifier did not fail clearly during $mode inspection"
  }

  for mode in \
    verify-failure \
    entitlements-failure \
    invalid-entitlements \
    whitespace-entitlements \
    array-entitlements \
    unsafe-allow-dyld \
    unsafe-apple-get-task \
    unsafe-plain-get-task \
    unsafe-suffix-get-task \
    unsafe-nested-entitlement \
    display-failure \
    empty-display \
    malformed-display \
    truncated-runtime \
    misleading-runtime \
    numeric-runtime-only \
    leading-comma-runtime \
    trailing-comma-runtime \
    doubled-comma-runtime \
    invalid-atom-runtime \
    duplicate-label-runtime \
    duplicate-record-runtime \
    no-runtime; do
    expect_vlc_verifier_reject "$mode"
  done
  grep -F 'entitlements is not a valid property list' \
    vlc-verifier-whitespace-entitlements.err >/dev/null ||
    fail "the VLC verifier treated whitespace entitlements as absence"
  grep -F 'code contains a caller-controlled injection entitlement' \
    vlc-verifier-unsafe-nested-entitlement.err >/dev/null ||
    fail "the VLC verifier did not reach the unsafe nested entitlement"
  for mode in \
    leading-comma-runtime \
    trailing-comma-runtime \
    doubled-comma-runtime \
    invalid-atom-runtime; do
    grep -F 'code-signing display has a malformed CodeDirectory record' \
      "vlc-verifier-$mode.err" >/dev/null ||
      fail "the VLC verifier did not reject malformed runtime labels"
  done
  grep -F 'code-signing display has duplicate flag labels' \
    vlc-verifier-duplicate-label-runtime.err >/dev/null ||
    fail "the VLC verifier did not reject a duplicate runtime label"
  grep -F 'code-signing display has no unique CodeDirectory record' \
    vlc-verifier-duplicate-record-runtime.err >/dev/null ||
    fail "the VLC verifier did not reject duplicate CodeDirectory records"

  mutated_vlc_bundle="$TMPDIR/VLC-mutated.app"
  cp -R "$vlc_verifier_bundle" "$mutated_vlc_bundle"
  mutated_vlc_pkginfo="$mutated_vlc_bundle/Contents/PkgInfo"
  chmod u+w "$mutated_vlc_bundle/Contents"

  expect_vlc_tree_reject() {
    mutation=$1
    if ${expectedVlcApp.verifier} "$mutated_vlc_bundle" \
      >"vlc-verifier-$mutation.out" 2>"vlc-verifier-$mutation.err"; then
      fail "the VLC package verifier accepted the $mutation tree mutation"
    fi
    grep -F 'complete xattr-free bundle hash does not match' \
      "vlc-verifier-$mutation.err" >/dev/null ||
      fail "the VLC package verifier did not reject the $mutation tree mutation first"
  }

  chmod u+x "$mutated_vlc_pkginfo"
  expect_vlc_tree_reject executable-mode
  chmod u-x "$mutated_vlc_pkginfo"

  mv "$mutated_vlc_pkginfo" "$TMPDIR/VLC-PkgInfo-original"
  ln -s Info.plist "$mutated_vlc_pkginfo"
  expect_vlc_tree_reject entry-type
  rm "$mutated_vlc_pkginfo"
  mv "$TMPDIR/VLC-PkgInfo-original" "$mutated_vlc_pkginfo"

  chmod u+w "$mutated_vlc_pkginfo"
  printf X >>"$mutated_vlc_pkginfo"
  expect_vlc_tree_reject file-content

  vlc_hostile_fixture="$TMPDIR/VLC-hostile-fixture.app"
  mkdir -p "$vlc_hostile_fixture/Contents/MacOS"
  printf '\317\372\355\376fixture-main' \
    >"$vlc_hostile_fixture/Contents/MacOS/VLC"
  chmod 0755 "$vlc_hostile_fixture/Contents/MacOS/VLC"

  write_vlc_fixture_info() {
    ${pkgs.python3}/bin/python3 -I - \
      "$vlc_hostile_fixture/Contents/Info.plist" "$1" <<'PY'
  import pathlib
  import plistlib
  import sys

  path = pathlib.Path(sys.argv[1])
  mode = sys.argv[2]
  values = {
      "CFBundleExecutable": "VLC",
      "CFBundleIdentifier": "org.videolan.vlc",
      "CFBundleShortVersionString": "3.0.23",
      "CFBundleVersion": "3.0.23",
  }
  if mode == "invalid":
      path.write_bytes(b"not a property list")
  elif mode == "array":
      path.write_bytes(plistlib.dumps([]))
  else:
      if mode == "wrong-identifier":
          values["CFBundleIdentifier"] = "org.example.vlc"
      elif mode != "valid":
          raise AssertionError(mode)
      path.write_bytes(plistlib.dumps(values, sort_keys=True))
  PY
  }

  run_vlc_hostile_fixture() {
    fixture_hash=$(
      ${pkgs.python3}/bin/python3 -I ${hashVlcFixture} "$vlc_hostile_fixture"
    )
    ${pkgs.python3}/bin/python3 -I ${expectedVlcApp.verifierProgram} \
      ${fakeVlcCodesign}/bin/codesign \
      "$fixture_hash" 3.0.23 "$vlc_hostile_fixture"
  }

  expect_vlc_hostile_fixture_reject() {
    mutation=$1
    expected_message=$2
    : >"$vlc_verifier_log"
    if run_vlc_hostile_fixture \
      >"vlc-hostile-$mutation.out" 2>"vlc-hostile-$mutation.err"; then
      fail "the VLC verifier accepted the $mutation hostile fixture"
    fi
    grep -F "$expected_message" "vlc-hostile-$mutation.err" >/dev/null ||
      fail "the VLC verifier did not reject the $mutation hostile fixture clearly"
  }

  printf '%s\n' success >"$vlc_verifier_mode"
  write_vlc_fixture_info valid
  run_vlc_hostile_fixture \
    >vlc-hostile-valid.out 2>vlc-hostile-valid.err ||
    fail "the VLC verifier rejected the valid minimal fixture"

  write_vlc_fixture_info invalid
  expect_vlc_hostile_fixture_reject \
    invalid-info-plist 'Info.plist is not a valid property list'
  write_vlc_fixture_info array
  expect_vlc_hostile_fixture_reject \
    nondictionary-info-plist 'Info.plist is not a property-list dictionary'
  write_vlc_fixture_info wrong-identifier
  expect_vlc_hostile_fixture_reject \
    wrong-info-identifier 'Info.plist has the wrong bundle identifier'

  write_vlc_fixture_info valid
  write_fat_mach_o_fixture() {
    case "$1" in
      fat32-big-endian) printf '\312\376\272\276fixture-fat' ;;
      fat32-little-endian) printf '\276\272\376\312fixture-fat' ;;
      fat64-big-endian) printf '\312\376\272\277fixture-fat' ;;
      fat64-little-endian) printf '\277\272\376\312fixture-fat' ;;
      *) fail "unknown hostile fat Mach-O fixture $1" ;;
    esac >"$vlc_hostile_fixture/Contents/MacOS/fat-helper"
  }
  for fat_variant in \
    fat32-big-endian fat32-little-endian \
    fat64-big-endian fat64-little-endian; do
    write_fat_mach_o_fixture "$fat_variant"
    expect_vlc_hostile_fixture_reject \
      "fat-mach-o-$fat_variant" \
      'fat Mach-O code is outside the arm64 entitlement policy'
  done

  if /usr/bin/otool -L ${expectedVlc}/bin/vlc-telnet-launcher |
    grep -F '/Security.framework/' >/dev/null; then
    fail "production VLC parent links Security.framework"
  fi
  /usr/bin/otool -L ${expectedVlc}/libexec/vlc-telnet-keychain-helper |
    grep -F '/Security.framework/' >/dev/null ||
    fail "production VLC helper does not use Security.framework"
  /usr/bin/nm -u ${expectedVlc}/libexec/vlc-telnet-keychain-helper |
    grep -F '_SecItemCopyMatching' >/dev/null ||
    fail "production VLC helper does not import the system Keychain query"
  /usr/bin/nm ${vlcLauncher}/libexec/vlc-telnet-keychain-helper |
    grep -E '[[:space:]]T[[:space:]]_SecItemCopyMatching$' >/dev/null ||
    fail "the VLC behavior test did not interpose its Keychain fixture"
  /usr/bin/nm ${vlcProcPidinfoFailureLauncher}/libexec/vlc-telnet-keychain-helper |
    grep -E '[[:space:]]T[[:space:]]_SecItemCopyMatching$' >/dev/null ||
    fail "the proc failure test could consult the real Keychain"
  grep -F 'kSecReturnPersistentRef' ${expectedVlc.helperSource} >/dev/null ||
    fail "production VLC does not enumerate Keychain matches safely"
  grep -F 'kSecValuePersistentRef' ${expectedVlc.helperSource} >/dev/null ||
    fail "production VLC does not resolve its unique persistent reference"
  grep -F 'CFArrayGetCount(matches) != 1' ${expectedVlc.helperSource} >/dev/null ||
    fail "production VLC does not reject ambiguous Keychain matches"
  grep -F 'kSecUseAuthenticationUISkip' ${expectedVlc.helperSource} >/dev/null ||
    fail "production VLC may request authentication UI from launchd"
  grep -F 'POSIX_SPAWN_CLOEXEC_DEFAULT' \
    ${expectedVlc.source} >/dev/null ||
    fail "production VLC does not isolate the Keychain helper descriptors"
  grep -F 'F_DUPFD_CLOEXEC, 3' ${expectedVlc.source} >/dev/null ||
    fail "production VLC does not normalize its config to CLOEXEC FD 3"
  grep -F 'S_ISFIFO(metadata.st_mode)' ${expectedVlc.source} \
    ${expectedVlc.helperSource} >/dev/null ||
    fail "production VLC does not verify its config pipe"
  if grep -F 'fork(' ${expectedVlc.source} ${expectedVlc.helperSource} >/dev/null; then
    fail "production VLC retained a post-fork framework path"
  fi
  [ "$(grep -c 'SecItemCopyMatching' ${expectedVlc.helperSource})" -eq 2 ] ||
    fail "production VLC does not use the two-stage Keychain query"
  if grep -F 'SERVICE_TEST_' ${expectedVlc.source} ${expectedVlc.helperSource} >/dev/null \
    || grep -aF 'nix-config.vlc-telnet-fixture' \
      ${expectedVlc}/bin/vlc-telnet-launcher \
      ${expectedVlc}/libexec/vlc-telnet-keychain-helper >/dev/null; then
    fail "production VLC retained a test-only Keychain path"
  fi
  if grep -aF '/usr/bin/security' \
    ${expectedVlc}/bin/vlc-telnet-launcher \
    ${expectedVlc}/libexec/vlc-telnet-keychain-helper >/dev/null; then
    fail "production VLC retained the transforming security CLI"
  fi
  grep -F 'static const char vlc_bin[] = "${expectedVlcApp}/Applications/VLC.app/Contents/MacOS/VLC"' \
    ${expectedVlc.source} >/dev/null ||
    fail "production VLC does not pin the immutable application"
  grep -F 'static char vlc_home[] = "HOME=${expectedVlcHome}"' \
    ${expectedVlc.source} >/dev/null ||
    fail "production VLC does not isolate user data under an immutable HOME"
  if grep -F '_NSGetEnviron' ${expectedVlc.source} >/dev/null; then
    fail "production VLC forwards its inherited environment"
  fi
  for binary in \
    ${expectedVlc}/bin/vlc-telnet-launcher \
    ${expectedVlc}/libexec/vlc-telnet-keychain-helper; do
    /usr/bin/codesign --verify --strict "$binary"
    signature=$(/usr/bin/codesign --display --verbose=4 "$binary" 2>&1)
    grep -E 'flags=.*\([^)]*adhoc' <<<"$signature" >/dev/null
    grep -E 'flags=.*\([^)]*library-validation' <<<"$signature" >/dev/null
    grep -E 'flags=.*\([^)]*runtime' <<<"$signature" >/dev/null
    ${entitlementValidatorFixture}/bin/validate-vlc-entitlements "$binary" ||
      fail "production VLC launcher component has unsafe entitlements"
  done
  for entitlement_mode in error raw-only non-dictionary unsafe; do
    if SERVICE_TEST_ENTITLEMENT_MODE="$entitlement_mode" \
      ${entitlementValidatorFixture}/bin/validate-vlc-entitlements \
        ${expectedVlc}/bin/vlc-telnet-launcher \
        >"entitlements-$entitlement_mode.out" \
        2>"entitlements-$entitlement_mode.err"; then
      fail "the native entitlement validator accepted $entitlement_mode"
    fi
  done

  chmod 0644 "$credential_file"
  expect_mssql_reject permissive-credential-mode
  chmod 0600 "$credential_file"
  chmod 0400 "$credential_file"
  expect_mssql_reject restrictive-credential-mode
  chmod 0600 "$credential_file"

  for mode in 0755 0750 0500; do
    chmod "$mode" "$credential_directory"
    leaf_metadata=$(snapshot_tree "$trust_root")
    expect_mssql_reject "credential-directory-mode-$mode"
    [ "$(snapshot_tree "$trust_root")" = "$leaf_metadata" ] ||
      fail "MSSQL repaired credential-directory mode $mode"
    chmod 0700 "$credential_directory"

    chmod "$mode" "$data_directory"
    leaf_metadata=$(snapshot_tree "$trust_root")
    expect_mssql_reject "data-directory-mode-$mode"
    [ "$(snapshot_tree "$trust_root")" = "$leaf_metadata" ] ||
      fail "MSSQL repaired data-directory mode $mode"
    chmod 0700 "$data_directory"
  done

  mv "$credential_file" "$credential_directory/regular-environment"
  mkfifo "$credential_file"
  fifo_metadata=$(snapshot_tree "$trust_root")
  : >"$SERVICE_TEST_DOCKER_LOG"
  : >"$SERVICE_TEST_VALIDATOR_LOG"
  fifo_status=0
  ${pkgs.coreutils}/bin/timeout 5 "$mssql_command" \
    >credential-fifo.out 2>credential-fifo.err || fifo_status=$?
  [ "$fifo_status" -ne 0 ] || fail "MSSQL accepted a credential FIFO"
  [ "$fifo_status" -ne 124 ] || fail "MSSQL blocked while opening a credential FIFO"
  scan_mssql_artifacts credential-fifo
  [ ! -s "$SERVICE_TEST_DOCKER_LOG" ] ||
    fail "MSSQL ran Docker after rejecting a credential FIFO"
  [ "$(snapshot_tree "$trust_root")" = "$fifo_metadata" ] ||
    fail "MSSQL mutated the credential FIFO"
  rm "$credential_file"
  mv "$credential_directory/regular-environment" "$credential_file"

  mv "$credential_file" "$credential_directory/real-environment"
  ln -s real-environment "$credential_file"
  expect_mssql_reject credential-symlink
  rm "$credential_file"
  mv "$credential_directory/real-environment" "$credential_file"

  ln "$credential_file" "$credential_directory/second-link"
  expect_mssql_reject multiply-linked-credential
  rm "$credential_directory/second-link"

  for acl_path in "$trust_root" "$trust_root/nix-config" "$credential_directory" "$credential_file"; do
    /bin/chmod +a "everyone deny delete" "$acl_path"
    expect_mssql_reject credential-chain-acl
    /bin/chmod -N "$acl_path"
  done
  for acl_path in "$data_parent" "$data_directory"; do
    /bin/chmod +a "everyone deny delete" "$acl_path"
    expect_mssql_reject data-chain-acl
    /bin/chmod -N "$acl_path"
  done

  chmod 0770 "$trust_root/nix-config"
  expect_mssql_reject writable-credential-parent
  chmod 0700 "$trust_root/nix-config"
  chmod 0770 "$data_parent"
  expect_mssql_reject writable-data-parent
  chmod 0700 "$data_parent"

  printf 'MSSQL_SA_PASSWORD=Aa1!bbb\n' >"$credential_file"
  expect_mssql_reject seven-character-password
  printf 'MSSQL_SA_PASSWORD=abcdefgh\n' >"$credential_file"
  expect_mssql_reject weak-password
  printf 'MSSQL_SA_PASSWORD=abcdefg!\n' >"$credential_file"
  expect_mssql_reject two-class-password
  printf 'MSSQL_SA_PASSWORD=Äabcdef1\n' >"$credential_file"
  expect_mssql_reject non-ascii-uppercase-class
  printf 'MSSQL_SA_PASSWORD=Aabcdef١\n' >"$credential_file"
  expect_mssql_reject non-ascii-digit-class
  printf 'MSSQL_SA_PASSWORD=Äa1!xyz\n' >"$credential_file"
  expect_mssql_reject seven-character-multibyte-password
  printf 'MSSQL_SA_PASSWORD=Aa1!abc\377\n' >"$credential_file"
  expect_mssql_reject invalid-utf8-password
  printf 'MSSQL_SA_PASSWORD=Aa1!bbbb\r\n' >"$credential_file"
  expect_mssql_reject carriage-return-password
  printf 'MSSQL_SA_PASSWORD=Aa1!bb\000bb\n' >"$credential_file"
  expect_mssql_reject nul-password
  printf 'MSSQL_SA_PASSWORD_EXTRA=Aa1!bbbb\n' >"$credential_file"
  expect_mssql_reject near-miss-key
  printf 'MSSQL_SA_PASSWORD=Aa1!bbbb\nEXTRA=value\n' >"$credential_file"
  expect_mssql_reject extra-environment-entry
  long_password=Aa1!
  index=0
  while [ "$index" -lt 125 ]; do
    long_password="''${long_password}x"
    index=$((index + 1))
  done
  printf 'MSSQL_SA_PASSWORD=%s\n' "$long_password" >"$credential_file"
  unset long_password
  expect_mssql_reject 129-character-password

  # Exact and representative valid policy boundaries remain accepted.
  printf 'MSSQL_SA_PASSWORD=abcdef1!\n' >"$credential_file"
  expect_mssql_accept eight-character-three-class-password
  touch validator-short-pread
  expect_mssql_accept short-pread-loop
  rm validator-short-pread
  printf 'MSSQL_SA_PASSWORD=Äa1!xxxx\n' >"$credential_file"
  expect_mssql_accept multibyte-password
  maximum_password=Aa1!
  index=0
  while [ "$index" -lt 124 ]; do
    maximum_password="''${maximum_password}x"
    index=$((index + 1))
  done
  printf 'MSSQL_SA_PASSWORD=%s\n' "$maximum_password" >"$credential_file"
  unset maximum_password
  expect_mssql_accept 128-character-password

  # A later secret-bearing run carries its own canary; short-fragment checks
  # must follow this credential rather than the initial fixture.
  later_mssql_secret=$(printf '\361\201\202\203\341\204\205Aa1!later-mssql-canary')
  printf 'MSSQL_SA_PASSWORD=%s\n' "$later_mssql_secret" >"$credential_file"
  expect_mssql_accept later-mssql-canary
  ${pkgs.python3}/bin/python3 ${assertSecretAbsentProgram} \
    --assignments --verify-short-fragments "$mssql_secret_oracle"
  assert_short_fragment_mutants_rejected \
    assignments "$mssql_secret_oracle" later-mssql-canary \
    later-mssql-canary.out later-mssql-canary.err \
    "$SERVICE_TEST_DOCKER_LOG" "$SERVICE_TEST_VALIDATOR_LOG"

  suffix_only_scanner="$TMPDIR/assert-secret-absent-suffix-only.py"
  ${pkgs.python3}/bin/python3 -I - \
    ${assertSecretAbsentProgram} "$suffix_only_scanner" <<'PY'
  import pathlib
  import sys
  import textwrap

  source_path, destination_path = map(pathlib.Path, sys.argv[1:])
  source = source_path.read_text()
  original = textwrap.dedent("""\
      short_raw_variants = {
          canary[start:stop]
          for canary in short_canaries
          for start in range(len(canary))
          for stop in range(start + 1, len(canary) + 1)
      }
  """)
  mutant = textwrap.dedent("""\
      short_raw_variants = {
          canary[start:]
          for canary in short_canaries
          for start in range(len(canary))
      }
  """)
  if source.count(original) != 1:
      raise SystemExit("could not construct the suffix-only detector mutant")
  destination_path.write_text(source.replace(original, mutant))
  PY
  if (
    assert_short_fragment_mutants_rejected_with \
      "$suffix_only_scanner" assignments "$mssql_secret_oracle" \
      suffix-only-detector-mutant \
      later-mssql-canary.out later-mssql-canary.err \
      "$SERVICE_TEST_DOCKER_LOG" "$SERVICE_TEST_VALIDATOR_LOG"
  ) >suffix-only-mutant.out 2>suffix-only-mutant.err; then
    fail "the complete short-fragment matrix did not kill the suffix-only detector mutant"
  fi
  grep -F \
    'the suffix-only-detector-mutant scanner accepted a 1-byte raw leak mutant at offset 0' \
    suffix-only-mutant.err >/dev/null ||
    fail "the suffix-only detector mutant died for the wrong reason"
  rm suffix-only-mutant.out suffix-only-mutant.err

  ${pkgs.python3}/bin/python3 ${shortLeakMutantProgram} \
    --assignments base64url 0 7 \
    "$mssql_secret_oracle" fake-docker-canary.leak
  fake_docker_canary=$(cat fake-docker-canary.leak)
  : >"$SERVICE_TEST_DOCKER_LOG"
  # The embedded `85` is an ordinary token substring, while the framed
  # base64url value is the real current-canary leak.
  TMPDIR="$TMPDIR/ambient-85-collision" \
    SERVICE_TEST_FAKE_DOCKER_LEAK="$fake_docker_canary" \
    ${pkgs.python3}/bin/python3 ${fakeDockerProgram} \
      image inspect --format '{{.Id}}' \
      mcr.microsoft.com/mssql/server:2022-latest \
      >fake-docker-canary.out 2>fake-docker-canary.err
  grep -F '"secret_value_env_keys":["SERVICE_TEST_FAKE_DOCKER_LEAK"]' \
    "$SERVICE_TEST_DOCKER_LOG" >/dev/null ||
    fail "fake Docker did not follow the current credential canary"
  if ${pkgs.python3}/bin/python3 ${assertSecretAbsentProgram} \
    --assignments "$mssql_secret_oracle" "$SERVICE_TEST_DOCKER_LOG" \
    >fake-docker-scan.out 2>fake-docker-scan.err; then
    fail "the scanner accepted fake Docker's current-canary leak"
  fi
  grep -F "secret material entered $SERVICE_TEST_DOCKER_LOG" \
    fake-docker-scan.err >/dev/null ||
    fail "the fake Docker canary probe failed for the wrong reason"
  rm fake-docker-canary.leak fake-docker-canary.out fake-docker-canary.err \
    fake-docker-scan.out fake-docker-scan.err
  unset fake_docker_canary
  unset later_mssql_secret

  printf 'MSSQL_SA_PASSWORD=%s\n' "$mssql_secret" >"$credential_file"

  rm -f docker-info-attempts sleep.jsonl
  touch docker-info-retry
  expect_mssql_accept docker-info-retry info-retry
  rm docker-info-retry
  [ "$(cat docker-info-attempts)" = 2 ] ||
    fail "MSSQL did not retry Docker readiness exactly once"
  grep -F 'Waiting for Docker to be ready...' docker-info-retry.out >/dev/null ||
    fail "MSSQL did not report the Docker readiness retry"
  ${pkgs.python3}/bin/python3 - sleep.jsonl <<'PY'
  import json
  import pathlib
  import sys
  records = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
  assert records == [{"argv": ["5"], "environment": {}, "open_fds": [0, 1, 2]}], records
  PY

  mv "$data_directory" "$data_parent/data-real"
  chmod 0755 "$data_parent/data-real"
  ln -s data-real "$data_directory"
  referent_metadata=$(stat -c '%i:%u:%g:%a' "$data_parent/data-real")
  expect_mssql_reject data-directory-symlink
  [ "$(stat -c '%i:%u:%g:%a' "$data_parent/data-real")" = "$referent_metadata" ] ||
    fail "MSSQL changed a data-directory symlink referent"
  rm "$data_directory"
  mv "$data_parent/data-real" "$data_directory"
  chmod 0700 "$data_directory"

  record_mssql_secret
  trust_tree_before=$(snapshot_tree "$trust_root")
  : >"$SERVICE_TEST_DOCKER_LOG"
  : >"$SERVICE_TEST_VALIDATOR_LOG"
  touch docker-invalid-image-id
  if "$mssql_command" >mssql-invalid-image.out 2>mssql-invalid-image.err; then
    fail "MSSQL accepted an invalid pulled image identity"
  fi
  rm docker-invalid-image-id
  scan_mssql_artifacts mssql-invalid-image
  grep -F 'the pulled MSSQL image identity is invalid' \
    mssql-invalid-image.err >/dev/null ||
    fail "MSSQL image-identity rejection was unclear"
  ${pkgs.python3}/bin/python3 ${assertDockerLogProgram} \
    image-invalid "$SERVICE_TEST_DOCKER_LOG" "$data_directory"
  [ "$(snapshot_tree "$trust_root")" = "$trust_tree_before" ] ||
    fail "MSSQL mutated the managed tree while rejecting an invalid image"

  record_mssql_secret
  : >"$SERVICE_TEST_DOCKER_LOG"
  : >"$SERVICE_TEST_VALIDATOR_LOG"
  touch docker-swap-parent
  if "$mssql_command" >mssql-pull-swap.out 2>mssql-pull-swap.err; then
    fail "MSSQL accepted a credential-parent swap during pull"
  fi
  rm docker-swap-parent
  scan_mssql_artifacts mssql-pull-swap
  [ -L "$trust_root/nix-config" ] || fail "the credential swap fixture did not run"
  ${pkgs.python3}/bin/python3 ${assertDockerLogProgram} \
    pull-swap "$SERVICE_TEST_DOCKER_LOG" "$data_directory"
  rm "$trust_root/nix-config"
  mv "$trust_root/nix-config.trusted" "$trust_root/nix-config"

  record_mssql_secret
  trust_tree_before=$(snapshot_tree "$trust_root")
  : >"$SERVICE_TEST_DOCKER_LOG"
  : >"$SERVICE_TEST_VALIDATOR_LOG"
  touch docker-fail-mount-check
  if "$mssql_command" >mssql-mount-check.out 2>mssql-mount-check.err; then
    fail "MSSQL removed service despite a failed Docker bind probe"
  fi
  rm docker-fail-mount-check
  scan_mssql_artifacts mssql-mount-check
  grep -F 'the MSSQL data bind is unavailable to Docker' \
    mssql-mount-check.err >/dev/null ||
    fail "MSSQL bind-probe rejection was unclear"
  ${pkgs.python3}/bin/python3 ${assertDockerLogProgram} \
    mount-failure "$SERVICE_TEST_DOCKER_LOG" "$data_directory"
  [ "$(snapshot_tree "$trust_root")" = "$trust_tree_before" ] ||
    fail "MSSQL mutated the managed tree after a failed bind probe"

  record_mssql_secret
  : >"$SERVICE_TEST_DOCKER_LOG"
  : >"$SERVICE_TEST_VALIDATOR_LOG"
  touch docker-swap-after-mount
  if "$mssql_command" >mssql-mount-swap.out 2>mssql-mount-swap.err; then
    fail "MSSQL accepted a data swap after the Docker bind probe"
  fi
  rm docker-swap-after-mount
  scan_mssql_artifacts mssql-mount-swap
  [ -L "$data_directory" ] || fail "the post-mount data swap fixture did not run"
  ${pkgs.python3}/bin/python3 ${assertDockerLogProgram} \
    mount-swap "$SERVICE_TEST_DOCKER_LOG" "$data_directory"
  rm "$data_directory"
  mv "$data_parent/data.trusted" "$data_directory"

  record_mssql_secret
  : >"$SERVICE_TEST_DOCKER_LOG"
  : >"$SERVICE_TEST_VALIDATOR_LOG"
  touch docker-swap-data
  if "$mssql_command" >mssql-rm-swap.out 2>mssql-rm-swap.err; then
    fail "MSSQL accepted a data-directory swap during container removal"
  fi
  rm docker-swap-data
  scan_mssql_artifacts mssql-rm-swap
  [ -L "$data_directory" ] || fail "the data swap fixture did not run"
  ${pkgs.python3}/bin/python3 ${assertDockerLogProgram} \
    rm-swap "$SERVICE_TEST_DOCKER_LOG" "$data_directory"
  rm "$data_directory"
  mv "$data_parent/data.trusted" "$data_directory"

  record_mssql_secret
  : >"$SERVICE_TEST_DOCKER_LOG"
  : >"$SERVICE_TEST_VALIDATOR_LOG"
  touch docker-mutate-envfile
  if "$mssql_command" \
    >mssql-rm-credential-mutation.out 2>mssql-rm-credential-mutation.err; then
    fail "MSSQL accepted a retained credential changed during container removal"
  fi
  rm docker-mutate-envfile
  scan_mssql_artifacts mssql-rm-credential-mutation
  grep -F 'retained credential is not the configured credential file' \
    mssql-rm-credential-mutation.err >/dev/null ||
    fail "MSSQL credential-provenance rejection was unclear"
  ${pkgs.python3}/bin/python3 ${assertDockerLogProgram} \
    rm-credential-mutation "$SERVICE_TEST_DOCKER_LOG" "$data_directory"
  rm "$credential_file"
  mv "$credential_directory/environment.retained" "$credential_file"

  for mutation in content mode acl; do
    label="mssql-rm-credential-$mutation-mutation"
    record_mssql_secret
    credential_identity=$(stat -c '%d:%i' "$credential_file")
    : >"$SERVICE_TEST_DOCKER_LOG"
    : >"$SERVICE_TEST_VALIDATOR_LOG"
    touch "docker-mutate-envfile-$mutation"
    if "$mssql_command" >"$label.out" 2>"$label.err"; then
      fail "MSSQL accepted a same-inode credential $mutation mutation during container removal"
    fi
    rm "docker-mutate-envfile-$mutation"
    scan_mssql_artifacts "$label"
    [ "$(stat -c '%d:%i' "$credential_file")" = "$credential_identity" ] ||
      fail "the credential $mutation mutation replaced its inode"
    case "$mutation" in
      content)
        expected_error='the MSSQL password must use at least three required character classes'
        cp "$mssql_secret_oracle" "$credential_file"
        ;;
      mode)
        expected_error='the credential file must be singly linked, owner-only, and mode 600'
        chmod 0600 "$credential_file"
        ;;
      acl)
        expected_error='credential file must not have ACL entries'
        /bin/chmod -N "$credential_file"
        ;;
    esac
    grep -F "$expected_error" "$label.err" >/dev/null ||
      fail "MSSQL did not revalidate the same-inode credential $mutation mutation"
    ${pkgs.python3}/bin/python3 ${assertDockerLogProgram} \
      "rm-credential-$mutation-mutation" \
      "$SERVICE_TEST_DOCKER_LOG" "$data_directory"
    cmp -s "$credential_file" "$mssql_secret_oracle" ||
      fail "the credential $mutation fixture was not restored"
    [ "$(stat -c '%a' "$credential_file")" = 600 ] ||
      fail "the credential $mutation fixture left the wrong mode"
  done

  record_mssql_secret
  trust_tree_before=$(snapshot_tree "$trust_root")
  : >"$SERVICE_TEST_DOCKER_LOG"
  : >"$SERVICE_TEST_VALIDATOR_LOG"
  touch docker-fail-rm
  if "$mssql_command" >mssql-rm-failure.out 2>mssql-rm-failure.err; then
    fail "MSSQL ignored a failed container removal"
  fi
  rm docker-fail-rm
  scan_mssql_artifacts mssql-rm-failure
  grep -F 'the existing MSSQL container could not be removed' \
    mssql-rm-failure.err >/dev/null ||
    fail "MSSQL container-removal rejection was unclear"
  ${pkgs.python3}/bin/python3 ${assertDockerLogProgram} \
    rm-failure "$SERVICE_TEST_DOCKER_LOG" "$data_directory"
  [ "$(snapshot_tree "$trust_root")" = "$trust_tree_before" ] ||
    fail "MSSQL mutated the managed tree after failed container removal"

  record_mssql_secret
  trust_tree_before=$(snapshot_tree "$trust_root")
  : >"$SERVICE_TEST_DOCKER_LOG"
  : >"$SERVICE_TEST_VALIDATOR_LOG"
  touch docker-container-ambiguous
  if "$mssql_command" >mssql-container-ambiguous.out 2>mssql-container-ambiguous.err; then
    fail "MSSQL accepted an ambiguous existing-container result"
  fi
  rm docker-container-ambiguous
  scan_mssql_artifacts mssql-container-ambiguous
  grep -F 'the existing MSSQL container state is ambiguous' \
    mssql-container-ambiguous.err >/dev/null ||
    fail "MSSQL ambiguous-container rejection was unclear"
  ${pkgs.python3}/bin/python3 ${assertDockerLogProgram} \
    container-ambiguous "$SERVICE_TEST_DOCKER_LOG" "$data_directory"
  [ "$(snapshot_tree "$trust_root")" = "$trust_tree_before" ] ||
    fail "MSSQL mutated the managed tree for an ambiguous container"

  record_mssql_secret
  trust_tree_before=$(snapshot_tree "$trust_root")
  : >"$SERVICE_TEST_DOCKER_LOG"
  : >"$SERVICE_TEST_VALIDATOR_LOG"
  touch docker-container-absent
  "$mssql_command" >mssql-container-absent.out 2>mssql-container-absent.err ||
    fail "MSSQL rejected an absent old container"
  rm docker-container-absent
  scan_mssql_artifacts mssql-container-absent
  ${pkgs.python3}/bin/python3 ${assertDockerLogProgram} \
    container-absent "$SERVICE_TEST_DOCKER_LOG" "$data_directory"
  [ "$(snapshot_tree "$trust_root")" = "$trust_tree_before" ] ||
    fail "MSSQL mutated the managed tree without an existing container"

  record_mssql_secret
  trust_tree_before=$(snapshot_tree "$trust_root")
  : >"$SERVICE_TEST_DOCKER_LOG"
  : >"$SERVICE_TEST_VALIDATOR_LOG"
  if "$mssql_command" unexpected >mssql-args.out 2>mssql-args.err; then
    fail "MSSQL accepted caller arguments"
  fi
  scan_mssql_artifacts mssql-args
  [ ! -s "$SERVICE_TEST_DOCKER_LOG" ] || fail "MSSQL ran Docker after rejecting arguments"
  [ "$(snapshot_tree "$trust_root")" = "$trust_tree_before" ] ||
    fail "MSSQL mutated the managed tree while rejecting arguments"

  unset SERVICE_TEST_MSSQL_SECRET_FILE
  export SERVICE_TEST_SECRET_FILE
  vlc_secret=$(printf '\364\217\277\274\363\240\200\202vlc-runtime-sentinel-B8!')
  printf %s "$vlc_secret" >"$SERVICE_TEST_SECRET_FILE"
  chmod 0600 "$SERVICE_TEST_SECRET_FILE"
  ${pkgs.python3}/bin/python3 ${assertSecretAbsentProgram} \
    --verify-short-fragments "$SERVICE_TEST_SECRET_FILE"

  # The helper authenticates its exact signed parent before any Keychain query.
  mkfifo direct-helper.fifo
  ${pkgs.coreutils}/bin/cat direct-helper.fifo >direct-helper-pipe.out &
  direct_helper_reader=$!
  : >"$SERVICE_TEST_KEYCHAIN_LOG"
  direct_helper_status=0
  ${pkgs.coreutils}/bin/timeout 5 \
    ${vlcLauncher}/libexec/vlc-telnet-keychain-helper \
    >direct-helper.out 2>direct-helper.err 3>direct-helper.fifo ||
    direct_helper_status=$?
  [ "$direct_helper_status" -ne 0 ] ||
    fail "the VLC Keychain helper accepted a direct invocation"
  [ "$direct_helper_status" -ne 124 ] ||
    fail "the directly invoked VLC Keychain helper hung"
  wait "$direct_helper_reader"
  rm direct-helper.fifo
  grep -F 'vlc-telnet: Keychain helper failed' direct-helper.err >/dev/null ||
    fail "the direct helper rejection was unclear"
  [ ! -s direct-helper.out ] || fail "the directly invoked helper wrote config data"
  [ ! -s direct-helper-pipe.out ] ||
    fail "the directly invoked helper wrote to its config pipe"
  [ ! -s "$SERVICE_TEST_KEYCHAIN_LOG" ] ||
    fail "the directly invoked helper consulted Keychain"
  scan_vlc_artifacts \
    direct-helper.out direct-helper-pipe.out direct-helper.err \
    "$SERVICE_TEST_KEYCHAIN_LOG"

  # Prove the constructor fixture works, then prove Hardened Runtime ignores
  # caller-selected libraries and reaches the launcher's own argument check.
  dyld_marker="$TMPDIR/dyld-injection.marker"
  ${pkgs.coreutils}/bin/env \
    SERVICE_TEST_DYLD_MARKER="$dyld_marker" \
    DYLD_INSERT_LIBRARIES=${fakeDyldInjection}/lib/injection.dylib \
    ${fakeDyldInjection}/bin/host
  [ -s "$dyld_marker" ] || fail "the DYLD injection fixture did not run"
  rm "$dyld_marker"
  : >"$SERVICE_TEST_KEYCHAIN_LOG"
  dyld_status=0
  ${pkgs.coreutils}/bin/timeout 5 ${pkgs.coreutils}/bin/env \
    SERVICE_TEST_DYLD_MARKER="$dyld_marker" \
    DYLD_INSERT_LIBRARIES=${fakeDyldInjection}/lib/injection.dylib \
    ${vlcLauncher}/bin/vlc-telnet-launcher unexpected \
    >dyld-injection.out 2>dyld-injection.err || dyld_status=$?
  [ "$dyld_status" -ne 0 ] || fail "VLC accepted the injection test arguments"
  [ "$dyld_status" -ne 124 ] || fail "the hardened VLC launcher hung"
  [ ! -e "$dyld_marker" ] ||
    fail "Hardened Runtime loaded a caller-selected library before main"
  grep -F 'vlc-telnet: the launcher does not accept arguments' \
    dyld-injection.err >/dev/null ||
    fail "the hardened launcher did not reach its own argument rejection"
  [ ! -s dyld-injection.out ] || fail "the injection test executed VLC"
  [ ! -s "$SERVICE_TEST_KEYCHAIN_LOG" ] ||
    fail "the injection test consulted Keychain"
  scan_vlc_artifacts \
    dyld-injection.out dyld-injection.err "$SERVICE_TEST_KEYCHAIN_LOG"

  : >"$SERVICE_TEST_KEYCHAIN_LOG"
  if ${vlcProcPidinfoFailureLauncher}/bin/vlc-telnet-launcher \
    19<"$TMPDIR/fd-sentinel" \
    >vlc-proc-pidinfo-failure.out 2>vlc-proc-pidinfo-failure.err; then
    fail "VLC ignored a descriptor-enumeration failure"
  fi
  [ "$(cat vlc-proc-pidinfo-failure.err)" = \
    'vlc-telnet: could not close inherited descriptors' ] ||
    fail "VLC descriptor-enumeration failure was not generic"
  [ ! -s "$SERVICE_TEST_KEYCHAIN_LOG" ] ||
    fail "VLC consulted Keychain after descriptor enumeration failed"
  [ ! -s vlc-proc-pidinfo-failure.out ] ||
    fail "VLC executed after descriptor enumeration failed"
  scan_vlc_artifacts \
    vlc-proc-pidinfo-failure.out vlc-proc-pidinfo-failure.err \
    "$SERVICE_TEST_KEYCHAIN_LOG"

  expect_vlc_thread_reject \
    historical-thread \
    ${vlcHistoricalThreadLauncher}/bin/vlc-telnet-launcher \
    'vlc-telnet: the launcher is not safely single-threaded' -
  expect_vlc_thread_reject \
    live-thread \
    ${vlcLiveThreadLauncher}/bin/vlc-telnet-launcher \
    'vlc-telnet: the launcher is not safely single-threaded' -
  expect_vlc_thread_reject \
    post-helper-thread \
    ${vlcPostHelperThreadLauncher}/bin/vlc-telnet-launcher \
    'vlc-telnet: the launcher is not safely single-threaded' \
    contract,match,value
  expect_vlc_thread_reject \
    final-thread \
    ${vlcFinalThreadLauncher}/bin/vlc-telnet-launcher \
    'vlc-telnet: could not isolate the VLC config descriptor' \
    contract,match,value

  export SERVICE_TEST_SECURITY_FAULT=validity-failure
  expect_vlc_reject \
    parent-validity-failure \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' -
  [ "$(cat parent-validity-failure.err)" = \
    "$(printf '%s\n%s' \
      'vlc-telnet: Keychain helper failed' \
      'vlc-telnet: Keychain password retrieval failed')" ] ||
    fail "VLC parent-validity failure diagnostics were not generic"
  unset SERVICE_TEST_SECURITY_FAULT

  for security_fault in \
    missing-runtime \
    missing-library-validation \
    missing-valid \
    missing-hard \
    missing-kill \
    debugged \
    unsafe-entitlement; do
    export SERVICE_TEST_SECURITY_FAULT="$security_fault"
    expect_vlc_reject \
      "parent-$security_fault" \
      'vlc-telnet: Keychain helper failed' \
      'vlc-telnet: Keychain password retrieval failed' -
  done
  unset SERVICE_TEST_SECURITY_FAULT

  export SERVICE_TEST_SECURITY_FAULT=reparent-match
  expect_vlc_reject \
    reparent-after-match \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' contract,match
  export SERVICE_TEST_SECURITY_FAULT=reparent-value
  expect_vlc_reject \
    reparent-after-value \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' contract,match,value
  export SERVICE_TEST_SECURITY_FAULT=reparent-write
  expect_vlc_reject \
    reparent-before-write \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' contract,match,value
  unset SERVICE_TEST_SECURITY_FAULT

  # A caller-controlled HOME may contain a malicious user Lua interface, but
  # the executed VLC receives the immutable empty HOME from the launcher.
  malicious_home="$TMPDIR/malicious-home"
  malicious_lua="$malicious_home/Library/Application Support/org.videolan.vlc/lua/intf"
  mkdir -p "$malicious_lua"
  printf '%s\n' 'os.execute("touch caller-lua-ran")' >"$malicious_lua/telnet.lua"
  : >"$SERVICE_TEST_KEYCHAIN_LOG"
  if ! HOME="$malicious_home" ${pkgs.coreutils}/bin/timeout 5 \
    ${vlcLauncher}/bin/vlc-telnet-launcher \
    >malicious-home.out 2>malicious-home.err; then
    fail "VLC rejected an isolated caller HOME"
  fi
  assert_vlc_accept malicious-home - 0,1,2,3
  [ ! -e caller-lua-ran ] || fail "VLC loaded Lua from the caller's HOME"

  : >"$SERVICE_TEST_KEYCHAIN_LOG"
  (
    exec 3<"$TMPDIR/fd-sentinel" 19<"$TMPDIR/fd-sentinel"
    ulimit -n 16
    exec ${vlcLauncher}/bin/vlc-telnet-launcher \
      >descriptor-isolation.out 2>descriptor-isolation.err
  ) &
  launcher_pid=$!
  wait "$launcher_pid"
  assert_vlc_accept descriptor-isolation "$launcher_pid" 0,1,2,3

  # Opaque executables naturally contain arbitrary one-byte values. Exercise
  # the explicit binary contract: keep full, encoded, and eight-byte-window
  # checks, but reserve one-to-seven-byte canary checks for text/log artifacts.
  ${pkgs.python3}/bin/python3 - "$SERVICE_TEST_SECRET_FILE" . <<'PY'
  import pathlib
  import sys

  secret_path, artifact_directory = map(pathlib.Path, sys.argv[1:])
  secret = secret_path.read_bytes()
  window = b"\xf4\x8f\xbf\xbc\xf3\xa0\x80\x82"
  assert secret.startswith(window)
  encoded = {
      "hex-lower": b"f48fbfbcf3a08082",
      "hex-upper": b"F48FBFBCF3A08082",
      "base64-padded": b"9I+/vPOggII=",
      "base64-unpadded": b"9I+/vPOggII",
      "base64url-padded": b"9I-_vPOggII=",
      "base64url-unpadded": b"9I-_vPOggII",
  }
  assert len(set(encoded.values())) == len(encoded)
  assert encoded["hex-lower"] != encoded["hex-upper"]
  assert encoded["base64-padded"].removesuffix(b"=") == encoded["base64-unpadded"]
  assert encoded["base64url-padded"].removesuffix(b"=") == encoded["base64url-unpadded"]
  assert encoded["base64-padded"] != encoded["base64url-padded"]
  assert encoded["base64-unpadded"] != encoded["base64url-unpadded"]
  assert b"+/" in encoded["base64-padded"]
  assert b"-_" in encoded["base64url-padded"]
  benign = b"\0".join(bytes([value]) for value in range(256))
  (artifact_directory / "opaque-benign.bin").write_bytes(benign)
  leaks = {"full": secret, "window": window} | encoded
  for name, leak in leaks.items():
      (artifact_directory / f"opaque-{name}.bin").write_bytes(
          benign + b"\0" + leak + b"\0"
      )
  PY
  ${pkgs.python3}/bin/python3 ${assertSecretAbsentProgram} \
    --opaque-binary "$SERVICE_TEST_SECRET_FILE" opaque-benign.bin
  if ${pkgs.python3}/bin/python3 ${assertSecretAbsentProgram} \
    --opaque-binary --verify-short-fragments "$SERVICE_TEST_SECRET_FILE" \
    >opaque-combination.out 2>opaque-combination.err; then
    fail "the secret scanner combined opaque and short-fragment modes"
  fi
  grep -F 'opaque binaries do not support short-fragment verification' \
    opaque-combination.err >/dev/null ||
    fail "the secret scanner rejected opaque short fragments for the wrong reason"
  for opaque_mode in \
    full window \
    hex-lower hex-upper \
    base64-padded base64-unpadded \
    base64url-padded base64url-unpadded; do
    if ${pkgs.python3}/bin/python3 ${assertSecretAbsentProgram} \
      --opaque-binary "$SERVICE_TEST_SECRET_FILE" "opaque-$opaque_mode.bin" \
      >"opaque-$opaque_mode.out" 2>"opaque-$opaque_mode.err"; then
      fail "the opaque scanner accepted a $opaque_mode credential leak"
    fi
    grep -F "secret material entered opaque-$opaque_mode.bin" \
      "opaque-$opaque_mode.err" >/dev/null ||
      fail "the opaque scanner rejected a $opaque_mode leak for the wrong reason"
  done

  opaque_mutant_directory="$TMPDIR/opaque-detector-mutants"
  mkdir "$opaque_mutant_directory"
  ${pkgs.python3}/bin/python3 -I - \
    ${assertSecretAbsentProgram} "$opaque_mutant_directory" <<'PY'
  import pathlib
  import sys

  source_path, destination_directory = map(pathlib.Path, sys.argv[1:])
  source = source_path.read_text()
  start_marker = "encoded_variants = set()\nunpadded_encoded_variants = set()\n"
  end_marker = "substring_variants = raw_variants | encoded_variants\n"
  if source.count(start_marker) != 1 or source.count(end_marker) != 1:
      raise SystemExit("could not isolate the encoded detector branches")
  block_start = source.index(start_marker)
  block_end = source.index(end_marker, block_start)
  if block_end <= block_start:
      raise SystemExit("encoded detector branch markers are out of order")
  block = source[block_start:block_end]
  branches = {
      "hex-lower": "        value.hex().encode(),\n",
      "hex-upper": "        value.hex().upper().encode(),\n",
      "base64-padded": "        standard,\n",
      "base64-unpadded": "        (standard.rstrip(b\"=\"), standard),\n",
      "base64url-padded": "        urlsafe,\n",
      "base64url-unpadded": "        (urlsafe.rstrip(b\"=\"), urlsafe),\n",
  }
  for name, branch in branches.items():
      if block.count(branch) != 1:
          raise SystemExit(f"could not construct the {name} deletion mutant")
      mutant_block = block.replace(branch, "")
      mutant = source[:block_start] + mutant_block + source[block_end:]
      (destination_directory / f"{name}.py").write_text(mutant)
  PY
  for opaque_mode in \
    hex-lower hex-upper \
    base64-padded base64-unpadded \
    base64url-padded base64url-unpadded; do
    mutant="$opaque_mutant_directory/$opaque_mode.py"
    if ! ${pkgs.python3}/bin/python3 "$mutant" \
      --opaque-binary "$SERVICE_TEST_SECRET_FILE" "opaque-$opaque_mode.bin" \
      >"opaque-$opaque_mode-mutant.out" \
      2>"opaque-$opaque_mode-mutant.err"; then
      fail "the $opaque_mode artifact did not kill its detector deletion mutant"
    fi
    [ ! -s "opaque-$opaque_mode-mutant.out" ] ||
      fail "the $opaque_mode deletion mutant wrote unexpected output"
    [ ! -s "opaque-$opaque_mode-mutant.err" ] ||
      fail "the $opaque_mode deletion mutant wrote unexpected diagnostics"
  done
  ${pkgs.python3}/bin/python3 ${assertSecretAbsentProgram} \
    --opaque-binary \
    "$SERVICE_TEST_SECRET_FILE" ${vlcLauncher}/bin/vlc-telnet-launcher

  # A closed standard descriptor makes the pipe reader start below FD 3. The
  # launcher must normalize only the FIFO to FD 3 and preserve stdin as closed.
  : >"$SERVICE_TEST_KEYCHAIN_LOG"
  (
    exec 0<&-
    exec ${vlcLauncher}/bin/vlc-telnet-launcher \
      >closed-stdin.out 2>closed-stdin.err
  )
  assert_vlc_accept closed-stdin - 1,2,3

  # Non-ASCII UTF-8 and a later distinct canary must make a byte-for-byte
  # round trip through the pipe.
  printf '\362\206\207\210\342\211\276välid-密碼-A7!' \
    >"$SERVICE_TEST_SECRET_FILE"
  run_vlc_accept utf8-password
  ${pkgs.python3}/bin/python3 ${assertSecretAbsentProgram} \
    --verify-short-fragments "$SERVICE_TEST_SECRET_FILE"
  assert_short_fragment_mutants_rejected \
    raw "$SERVICE_TEST_SECRET_FILE" later-vlc-canary \
    utf8-password.out utf8-password.err "$SERVICE_TEST_KEYCHAIN_LOG"

  # The exact lower byte bound is accepted.
  printf '\001' >"$SERVICE_TEST_SECRET_FILE"
  run_vlc_accept one-byte-password

  # Mutation control: the downstream exclusions are exact. VLC-compatible
  # whitespace remains valid away from the edges, and 0x04 remains valid when
  # it is not the complete password.
  printf '%b' '\004A\040B\011C\013D\014E\004' >"$SERVICE_TEST_SECRET_FILE"
  run_vlc_accept interior-whitespace-and-nonexact-eot-password

  # The documented byte limit is accepted and still fits one atomic pipe write.
  ${pkgs.python3}/bin/python3 - "$SERVICE_TEST_SECRET_FILE" <<'PY'
  import pathlib
  import sys
  pathlib.Path(sys.argv[1]).write_bytes(b"x" * 492)
  PY
  run_vlc_accept maximum-password

  # Helper process isolation closes a live Security-created descriptor and
  # thread before the parent execs VLC.
  printf 'security-fd-confinement-A7!' >"$SERVICE_TEST_SECRET_FILE"
  export SERVICE_TEST_KEYCHAIN_OPEN_SECURITY_FD=1
  run_vlc_accept security-fd-confinement
  unset SERVICE_TEST_KEYCHAIN_OPEN_SECURITY_FD

  # A signalled helper must fail closed without hanging or inheriting the
  # caller's HOME or arbitrary environment.
  saved_caller_home=$HOME
  export HOME="$TMPDIR/untrusted-helper-home"
  export SERVICE_TEST_UNEXPECTED_HELPER_ENV=not-forwarded
  export SERVICE_TEST_KEYCHAIN_SIGNAL=1
  expect_vlc_reject \
    signalled-keychain-helper - \
    'vlc-telnet: Keychain password retrieval failed' contract,signal
  unset SERVICE_TEST_KEYCHAIN_SIGNAL
  unset SERVICE_TEST_UNEXPECTED_HELPER_ENV
  export HOME="$saved_caller_home"

  export SERVICE_TEST_KEYCHAIN_FAIL=1
  expect_vlc_reject \
    keychain-lookup-failure \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' \
    contract,match
  unset SERVICE_TEST_KEYCHAIN_FAIL
  export SERVICE_TEST_KEYCHAIN_DUPLICATE=1
  expect_vlc_reject \
    duplicate-keychain-item \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' \
    contract,match
  unset SERVICE_TEST_KEYCHAIN_DUPLICATE
  export SERVICE_TEST_KEYCHAIN_VALUE_FAIL=1
  expect_vlc_reject \
    keychain-value-failure \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' \
    contract,match,value
  unset SERVICE_TEST_KEYCHAIN_VALUE_FAIL
  : >"$SERVICE_TEST_SECRET_FILE"
  expect_vlc_reject \
    empty-keychain-password \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' \
    contract,match,value
  printf '%b' '\004' >"$SERVICE_TEST_SECRET_FILE"
  expect_vlc_reject \
    exact-eot-keychain-password \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' \
    contract,match,value

  # Mutation matrix: exercise both edges and every non-CR/LF byte stripped by
  # VLC 3.0.23's C-locale Lua %s pattern independently.
  for edge_whitespace in space tab vertical-tab form-feed; do
    case "$edge_whitespace" in
      space) edge_escape='\040' ;;
      tab) edge_escape='\011' ;;
      vertical-tab) edge_escape='\013' ;;
      form-feed) edge_escape='\014' ;;
    esac
    printf '%b%s' "$edge_escape" 'edge-safe-A7!' >"$SERVICE_TEST_SECRET_FILE"
    expect_vlc_reject \
      "leading-$edge_whitespace-keychain-password" \
      'vlc-telnet: Keychain helper failed' \
      'vlc-telnet: Keychain password retrieval failed' \
      contract,match,value
    printf '%s%b' 'edge-safe-A7!' "$edge_escape" >"$SERVICE_TEST_SECRET_FILE"
    expect_vlc_reject \
      "trailing-$edge_whitespace-keychain-password" \
      'vlc-telnet: Keychain helper failed' \
      'vlc-telnet: Keychain password retrieval failed' \
      contract,match,value
  done
  printf 'trailing-line-feed\n' >"$SERVICE_TEST_SECRET_FILE"
  expect_vlc_reject \
    trailing-line-feed-password \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' \
    contract,match,value
  printf 'first\nsecond' >"$SERVICE_TEST_SECRET_FILE"
  expect_vlc_reject \
    line-feed-password \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' \
    contract,match,value
  printf 'first\rsecond' >"$SERVICE_TEST_SECRET_FILE"
  expect_vlc_reject \
    carriage-return-keychain-password \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' \
    contract,match,value
  printf 'first\0second' >"$SERVICE_TEST_SECRET_FILE"
  expect_vlc_reject \
    nul-keychain-password \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' \
    contract,match,value
  printf 'first\377second' >"$SERVICE_TEST_SECRET_FILE"
  expect_vlc_reject \
    invalid-utf8-keychain-password \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' \
    contract,match,value
  ${pkgs.python3}/bin/python3 - "$SERVICE_TEST_SECRET_FILE" <<'PY'
  import pathlib
  import sys
  pathlib.Path(sys.argv[1]).write_bytes(b"x" * 493)
  PY
  expect_vlc_reject \
    oversized-keychain-password \
    'vlc-telnet: Keychain helper failed' \
    'vlc-telnet: Keychain password retrieval failed' \
    contract,match,value

  : >"$SERVICE_TEST_KEYCHAIN_LOG"
  if ${vlcLauncher}/bin/vlc-telnet-launcher unexpected \
    >vlc-args.out 2>vlc-args.err; then
    fail "VLC accepted caller arguments"
  fi
  grep -F 'does not accept arguments' vlc-args.err >/dev/null ||
    fail "VLC argument failure is unclear"
  [ ! -s "$SERVICE_TEST_KEYCHAIN_LOG" ] ||
    fail "VLC queried Keychain after rejecting caller arguments"
  [ ! -s vlc-args.out ] ||
    fail "VLC executed after rejecting caller arguments"
  scan_vlc_artifacts vlc-args.out vlc-args.err \
    "$SERVICE_TEST_KEYCHAIN_LOG"

  if grep -F -- '--telnet-password=secret' \
    ${src}/config/launchd.nix ${src}/config/launchd-service-launchers.nix >/dev/null; then
    fail "the literal VLC credential remains in generated source"
  fi
  if grep -F 'find-generic-password' \
    ${src}/config/launchd-service-launchers.nix >/dev/null; then
    fail "VLC still relies on the transforming security CLI"
  fi
  if grep -F 'MSSQL_SA_PASSWORD=$MSSQL_SA_PASSWORD' \
    ${src}/config/launchd.nix ${src}/config/launchd-service-launchers.nix >/dev/null; then
    fail "the MSSQL credential still enters Docker argv"
  fi

  touch "$out"
''
