{
  lib,
  runCommandCC,
  writeText,
}:

let
  bundleIdentifier = "com.agentdeck.conductor-bridge";
  bundleName = "Agent Deck Conductor Bridge";
  executableName = "agent-deck-conductor-bridge";
  appRelativePath = "Applications/${bundleName}.app";

  launcherSource = writeText "agent-deck-conductor-bridge.c" ''
    #define _POSIX_C_SOURCE 200809L
    #include <errno.h>
    #include <signal.h>
    #include <spawn.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <sys/wait.h>
    #include <unistd.h>

    extern char **environ;

    static volatile sig_atomic_t child_pid = -1;

    static void forward_signal(int signal_number) {
        int saved_errno = errno;
        pid_t pid = (pid_t)child_pid;
        if (pid > 0) (void)kill(pid, signal_number);
        errno = saved_errno;
    }

    static int fail(const char *operation, int error_number) {
        fprintf(
            stderr, "agent-deck-conductor-bridge: %s: %s\n",
            operation, strerror(error_number)
        );
        return EXIT_FAILURE;
    }

    static int mirror_signal(int signal_number) {
        struct sigaction action = { .sa_handler = SIG_DFL };
        sigemptyset(&action.sa_mask);
        (void)sigaction(signal_number, &action, NULL);

        sigset_t signal_set;
        sigemptyset(&signal_set);
        sigaddset(&signal_set, signal_number);
        (void)sigprocmask(SIG_UNBLOCK, &signal_set, NULL);
        (void)raise(signal_number);
        return 128 + signal_number;
    }

    int main(int argc, char **argv) {
        if (argc < 2 || argv[1][0] != '/') {
            fputs(
                "agent-deck-conductor-bridge: expected an absolute child executable\n",
                stderr
            );
            return EXIT_FAILURE;
        }

        sigset_t forwarded_signals;
        sigemptyset(&forwarded_signals);
        sigaddset(&forwarded_signals, SIGHUP);
        sigaddset(&forwarded_signals, SIGINT);
        sigaddset(&forwarded_signals, SIGQUIT);
        sigaddset(&forwarded_signals, SIGTERM);
        sigset_t inherited_mask;
        if (sigprocmask(SIG_BLOCK, &forwarded_signals, &inherited_mask) != 0) {
            return fail("could not block forwarded signals", errno);
        }

        struct sigaction action = { .sa_handler = forward_signal };
        sigemptyset(&action.sa_mask);
        const int signal_numbers[] = { SIGHUP, SIGINT, SIGQUIT, SIGTERM };
        for (size_t index = 0; index < sizeof(signal_numbers) / sizeof(signal_numbers[0]); ++index) {
            if (sigaction(signal_numbers[index], &action, NULL) != 0) {
                return fail("could not install a signal handler", errno);
            }
        }

        posix_spawnattr_t attributes;
        int result = posix_spawnattr_init(&attributes);
        if (result != 0) return fail("could not initialize spawn attributes", result);

        result = posix_spawnattr_setsigmask(&attributes, &inherited_mask);
        if (result == 0) {
            result = posix_spawnattr_setsigdefault(&attributes, &forwarded_signals);
        }
        if (result == 0) {
            result = posix_spawnattr_setflags(
                &attributes, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
            );
        }

        pid_t pid = -1;
        if (result == 0) {
            result = posix_spawn(&pid, argv[1], NULL, &attributes, &argv[1], environ);
        }
        (void)posix_spawnattr_destroy(&attributes);
        if (result != 0) return fail("could not start the bridge", result);

        child_pid = pid;
        if (sigprocmask(SIG_SETMASK, &inherited_mask, NULL) != 0) {
            int error_number = errno;
            (void)kill(pid, SIGTERM);
            (void)waitpid(pid, NULL, 0);
            return fail("could not restore the inherited signal mask", error_number);
        }

        siginfo_t child_info;
        int waited;
        do {
            waited = waitid(P_PID, (id_t)pid, &child_info, WEXITED | WNOWAIT);
        } while (waited < 0 && errno == EINTR);
        if (waited < 0) return fail("could not observe the bridge", errno);

        if (sigprocmask(SIG_BLOCK, &forwarded_signals, NULL) != 0) {
            return fail("could not disable signal forwarding", errno);
        }
        child_pid = -1;

        int status = 0;
        pid_t reaped;
        do {
            reaped = waitpid(pid, &status, 0);
        } while (reaped < 0 && errno == EINTR);
        if (reaped < 0) return fail("could not reap the bridge", errno);
        if (WIFEXITED(status)) return WEXITSTATUS(status);
        if (WIFSIGNALED(status)) return mirror_signal(WTERMSIG(status));
        return EXIT_FAILURE;
    }
  '';

  infoPlist = writeText "agent-deck-conductor-bridge-Info.plist" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key>
      <string>en</string>
      <key>CFBundleDisplayName</key>
      <string>${bundleName}</string>
      <key>CFBundleExecutable</key>
      <string>${executableName}</string>
      <key>CFBundleIdentifier</key>
      <string>${bundleIdentifier}</string>
      <key>CFBundleInfoDictionaryVersion</key>
      <string>6.0</string>
      <key>CFBundleName</key>
      <string>${bundleName}</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleShortVersionString</key>
      <string>1.0</string>
      <key>CFBundleVersion</key>
      <string>1</string>
      <key>LSBackgroundOnly</key>
      <true/>
    </dict>
    </plist>
  '';
in
runCommandCC "agent-deck-conductor-bridge-launcher"
  {
    passthru = {
      inherit
        appRelativePath
        bundleIdentifier
        bundleName
        executableName
        infoPlist
        launcherSource
        ;
      tccEntitlements = { };
    };
    meta.platforms = lib.platforms.darwin;
  }
  ''
    app="$out/${appRelativePath}"
    executable="$app/Contents/MacOS/${executableName}"
    mkdir -p "$app/Contents/MacOS"
    install -m 0444 ${infoPlist} "$app/Contents/Info.plist"
    printf 'APPL????' > "$app/Contents/PkgInfo"
    "$CC" -std=c11 -Wall -Wextra -Werror \
      ${launcherSource} -o "$executable"

    /usr/bin/codesign --force --sign - \
      --identifier ${lib.escapeShellArg bundleIdentifier} \
      --options runtime --timestamp=none "$app"
    /usr/bin/codesign --verify --strict --verbose=4 "$app"

    signature=$(/usr/bin/codesign --display --verbose=4 "$executable" 2>&1)
    grep -F ${lib.escapeShellArg "Identifier=${bundleIdentifier}"} <<<"$signature" >/dev/null
    grep -E 'flags=.*\([^)]*adhoc' <<<"$signature" >/dev/null
    grep -E 'flags=.*\([^)]*runtime' <<<"$signature" >/dev/null

    /usr/bin/codesign --display --entitlements - --xml \
      "$executable" > actual-entitlements.plist
    if [ -s actual-entitlements.plist ]; then
      /usr/bin/plutil -lint actual-entitlements.plist >/dev/null
      ! grep -F '<key>' actual-entitlements.plist >/dev/null
    fi
  ''
