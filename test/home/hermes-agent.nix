{
  darwinConfigurations,
  homeConfigurations,
  pkgs,
}:

let
  inherit (pkgs) lib;
  heraSystem = darwinConfigurations.hera.config;
  clioSystem = darwinConfigurations.clio.config;
  hera = heraSystem.home-manager.users.johnw;
  clio = clioSystem.home-manager.users.johnw;
  linuxHomes = map (configuration: configuration.config) (builtins.attrValues homeConfigurations);

  service = hera.services.hermes-agent;
  servicePackage = service.package;
  runtimePackage = hera.johnw.hermesAgent.runtimePackage;
  operatorPackage = lib.findFirst (
    package: lib.getName package == "hermes-agent-ops"
  ) null hera.home.packages;
  launcher = servicePackage.hermesAgentServiceLauncher;
  launcherApp = "${launcher}/${launcher.appRelativePath}";
  atomicReplace = "${launcher}/${launcher.atomicReplaceRelativePath}";
  launcherExecutable = "${launcherApp}/Contents/MacOS/${launcher.executableName}";
  fixedApp = "/Users/johnw/Applications/Hermes Agent Service.app";
  fixedExecutable = "${fixedApp}/Contents/MacOS/${launcher.executableName}";
  activation = hera.home.activation.installHermesAgentServiceApp;
  activationText = builtins.unsafeDiscardStringContext activation.data;
  activationMktempParts = lib.splitString "/usr/bin/mktemp" activationText;
  activationCodesignParts = lib.splitString "/usr/bin/codesign --force" activationText;
  activationReplaceParts = lib.splitString (builtins.unsafeDiscardStringContext atomicReplace) activationText;
  agent = hera.launchd.agents.hermes-agent;
  environment = agent.config.EnvironmentVariables;
  hermesAgents = lib.filterAttrs (name: _: lib.hasPrefix "hermes" name) hera.launchd.agents;
  expectedPath = lib.concatStringsSep ":" [
    "/Users/johnw/src/scripts"
    "${hera.home.profileDirectory}/bin"
    "/Users/johnw/.local/bin"
    "/Users/johnw/work/positron/bin"
    "/nix/var/nix/profiles/default/bin"
    "/usr/local/bin"
    "/usr/local/zfs/bin"
    "/opt/homebrew/bin"
    "/opt/homebrew/opt/node@22/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];
  lifecycleAbsent =
    home:
    home.johnw.hermesAgent.runtimePackage == null
    && !home.services.hermes-agent.enable
    && !(home.home.activation ? installHermesAgentServiceApp)
    && !(home.launchd.agents ? hermes-agent);
  forbiddenSchedulingMechanisms = [
    "taskpolicy"
    "cpuset"
    "sched_setaffinity"
    "AllowedCPUs"
  ];
  moduleSource = builtins.readFile ../../config/hermes-agent.nix;
in
assert service.enable;
assert service.gateway.enable;
assert service.backend.mode == "none";
assert service.installPackage;
assert runtimePackage != null;
assert operatorPackage != null;
assert !(builtins.any (package: lib.getName package == "hermes-agent-ops") clio.home.packages);
assert builtins.all (
  home: !(builtins.any (package: lib.getName package == "hermes-agent-ops") home.home.packages)
) linuxHomes;
assert servicePackage.hermesAgentRuntimePackage.drvPath == runtimePackage.drvPath;
assert builtins.any (package: package.drvPath == servicePackage.drvPath) hera.home.packages;
assert builtins.attrNames hermesAgents == [ "hermes-agent" ];
assert agent.enable;
assert agent.domain == "gui";
assert agent.waitForNixStore;
assert agent.config.Label == "org.nix-community.home.hermes-agent";
assert
  agent.config.ProgramArguments == [
    "${servicePackage}/bin/hermes"
    "gateway"
  ];
assert agent.config.AssociatedBundleIdentifiers == [ "com.newartisans.hermes-agent" ];
assert agent.config.ProcessType == "Standard";
assert agent.config.Umask == 63;
assert agent.config.StandardOutPath == "/Users/johnw/.hermes/logs/gateway.log";
assert agent.config.StandardErrorPath == "/Users/johnw/.hermes/logs/gateway.err.log";
assert environment.HERMES_HOME == "/Users/johnw/.hermes";
assert environment.HERMES_MANAGED == "home-manager";
assert environment.HOME == "/Users/johnw";
assert environment.USER == "johnw";
assert environment.LOGNAME == "johnw";
assert environment.PATH == expectedPath;
assert environment.XDG_CONFIG_HOME == "/Users/johnw/.config";
assert environment.XDG_DATA_HOME == "/Users/johnw/.local/share";
assert environment.XDG_STATE_HOME == "/Users/johnw/.local/state";
assert environment.GNUPGHOME == "/Users/johnw/.config/gnupg";
assert environment.SSH_AUTH_SOCK == "/Users/johnw/.config/gnupg/S.gpg-agent.ssh";
assert environment.SSL_CERT_FILE == hera.home.sessionVariables.SSL_CERT_FILE;
assert environment.NIX_CONFIG == "max-jobs = 1\ncores = 8";
assert environment.HTTP_PROXY == "";
assert environment.HTTPS_PROXY == "";
assert environment.ALL_PROXY == "";
assert environment.NO_PROXY == "*";
assert environment.http_proxy == "";
assert environment.https_proxy == "";
assert environment.all_proxy == "";
assert environment.no_proxy == "*";
assert !(environment ? GPG_TTY);
assert activation.before == [ "setupLaunchAgents" ];
assert
  activation.after == [
    "linkGeneration"
    "hermesAgentSetup"
  ];
assert lib.hasInfix fixedApp activationText;
assert lib.hasInfix "Apple Development: jwiegley@gmail.com (Y546N259NB)" activationText;
assert lib.hasInfix "/usr/bin/security find-identity -v -p codesigning" activationText;
assert lib.hasInfix "certificate leaf[subject.OU] = \"Y546N259NB\"" activationText;
assert lib.hasInfix (builtins.unsafeDiscardStringContext atomicReplace) activationText;
assert lib.hasInfix "/usr/bin/codesign --verify --strict" activationText;
assert builtins.length activationMktempParts == 2;
assert lib.hasInfix "trap cleanup_candidate EXIT" (builtins.head activationMktempParts);
assert builtins.length activationCodesignParts == 2;
assert lib.hasInfix "/bin/chmod -R u+rwX,go-w \"$candidate\"" (
  builtins.head activationCodesignParts
);
assert builtins.length activationReplaceParts == 2;
assert lib.hasInfix "/bin/chmod -R u+rwX \"$candidate\"" (builtins.elemAt activationReplaceParts 1);
assert lib.hasInfix "trap 'terminate_candidate 129' HUP" activationText;
assert lib.hasInfix "trap 'terminate_candidate 130' INT" activationText;
assert lib.hasInfix "trap 'terminate_candidate 143' TERM" activationText;
assert !(lib.hasInfix "--sign -" activationText);
assert !(lib.hasInfix "tailscale" activationText);
assert builtins.all (
  mechanism: !(lib.hasInfix mechanism moduleSource)
) forbiddenSchedulingMechanisms;
assert lifecycleAbsent clio;
assert builtins.all lifecycleAbsent linuxHomes;
assert lib.hasInfix "johnw ALL=(ALL:ALL) NOPASSWD: ALL" heraSystem.security.sudo.extraConfig;
assert !(lib.hasInfix "johnw ALL=(ALL:ALL) NOPASSWD: ALL" clioSystem.security.sudo.extraConfig);
pkgs.runCommand "hermes-agent-macos-service" { } ''
  launcher=${lib.escapeShellArg launcherExecutable}
  atomic_replace=${lib.escapeShellArg atomicReplace}

  /usr/bin/plutil -lint ${lib.escapeShellArg "${launcherApp}/Contents/Info.plist"} >/dev/null
  [ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - \
    ${lib.escapeShellArg "${launcherApp}/Contents/Info.plist"})" = \
    ${lib.escapeShellArg launcher.bundleIdentifier} ]
  [ "$(/usr/bin/plutil -extract CFBundleExecutable raw -o - \
    ${lib.escapeShellArg "${launcherApp}/Contents/Info.plist"})" = \
    ${lib.escapeShellArg launcher.executableName} ]
  [ "$(/usr/bin/plutil -extract LSBackgroundOnly raw -o - \
    ${lib.escapeShellArg "${launcherApp}/Contents/Info.plist"})" = true ]
  [ -n "$(/usr/bin/plutil -extract NSLocalNetworkUsageDescription raw -o - \
    ${lib.escapeShellArg "${launcherApp}/Contents/Info.plist"})" ]

  signed_candidate="$PWD/Hermes Agent Service.app"
  /usr/bin/ditto --rsrc --extattr ${lib.escapeShellArg launcherApp} "$signed_candidate"
  [ ! -w "$signed_candidate/Contents/MacOS/${launcher.executableName}" ]
  /bin/chmod -R u+rwX,go-w "$signed_candidate"
  [ -w "$signed_candidate/Contents/MacOS/${launcher.executableName}" ]
  /usr/bin/codesign --force --sign - \
    --identifier ${lib.escapeShellArg launcher.bundleIdentifier} \
    --options runtime --timestamp=none "$signed_candidate"
  /usr/bin/codesign --verify --strict --verbose=4 "$signed_candidate"
  [ -f "$signed_candidate/Contents/_CodeSignature/CodeResources" ]

  ${pkgs.gnugrep}/bin/grep -F 'posix_spawn(&pid' ${launcher.launcherSource} >/dev/null
  ${pkgs.gnugrep}/bin/grep -F 'waitid(P_PID' ${launcher.launcherSource} >/dev/null
  ${pkgs.gnugrep}/bin/grep -F 'WNOWAIT' ${launcher.launcherSource} >/dev/null
  ${pkgs.gnugrep}/bin/grep -F 'forward_signal' ${launcher.launcherSource} >/dev/null
  ${pkgs.gnugrep}/bin/grep -F 'mirror_signal' ${launcher.launcherSource} >/dev/null
  ${pkgs.gnugrep}/bin/grep -F ${lib.escapeShellArg fixedExecutable} \
    ${servicePackage.hermesAgentServiceEntry}/bin/hermes >/dev/null

  if "$launcher" > no-child.out 2> no-child.err; then
    echo "Hermes service launcher accepted an empty command" >&2
    exit 1
  fi
  [ ! -s no-child.out ]
  ${pkgs.gnugrep}/bin/grep -F 'expected an absolute child executable' no-child.err >/dev/null

  if "$launcher" /bin/sh -c 'exit 23'; then
    echo "Hermes service launcher lost the child exit status" >&2
    exit 1
  else
    child_status=$?
  fi
  [ "$child_status" -eq 23 ]

  probe="$PWD/hermes-process-probe"
  probe_cwd="$PWD/hermes-process-cwd"
  ${pkgs.coreutils}/bin/mkdir -p "$probe_cwd"
  ${pkgs.coreutils}/bin/cat > "$probe" <<'EOF'
  #!/bin/sh
  set -eu
  IFS= read -r input
  printf 'argv0=%s\nargv1=%s\nargv2=%s\nenv=%s\ncwd=%s\nstdin=%s\n' \
    "$0" "$1" "$2" "$HERMES_PROCESS_ENV" "$PWD" "$input"
  printf 'stderr=%s\n' "$HERMES_PROCESS_ENV" >&2
  EOF
  ${pkgs.coreutils}/bin/chmod 0755 "$probe"
  printf 'probe-input\n' | (
    cd "$probe_cwd"
    HERMES_PROCESS_ENV=preserved \
      "$launcher" "$probe" first 'second argument'
  ) > probe.stdout 2> probe.stderr
  ${pkgs.gnugrep}/bin/grep -Fx "argv0=$probe" probe.stdout >/dev/null
  ${pkgs.gnugrep}/bin/grep -Fx 'argv1=first' probe.stdout >/dev/null
  ${pkgs.gnugrep}/bin/grep -Fx 'argv2=second argument' probe.stdout >/dev/null
  ${pkgs.gnugrep}/bin/grep -Fx 'env=preserved' probe.stdout >/dev/null
  ${pkgs.gnugrep}/bin/grep -Fx "cwd=$probe_cwd" probe.stdout >/dev/null
  ${pkgs.gnugrep}/bin/grep -Fx 'stdin=probe-input' probe.stdout >/dev/null
  [ "$(< probe.stderr)" = 'stderr=preserved' ]

  signal_probe="$PWD/hermes-signal-probe"
  signal_ready="$PWD/hermes-signal-ready"
  signal_forwarded="$PWD/hermes-signal-forwarded"
  ${pkgs.coreutils}/bin/cat > "$signal_probe" <<'EOF'
  #!/bin/sh
  set -eu
  trap 'printf forwarded > "$1"; exit 42' TERM
  : > "$2"
  for _ in $(${pkgs.coreutils}/bin/seq 1 100); do /bin/sleep 0.1; done
  exit 97
  EOF
  ${pkgs.coreutils}/bin/chmod 0755 "$signal_probe"
  "$launcher" "$signal_probe" "$signal_forwarded" "$signal_ready" &
  supervisor=$!
  for _ in $(${pkgs.coreutils}/bin/seq 1 100); do
    [ ! -e "$signal_ready" ] || break
    /bin/sleep 0.05
  done
  [ -e "$signal_ready" ]
  /bin/kill -TERM "$supervisor"
  if wait "$supervisor"; then
    echo "Hermes service launcher lost the forwarded child status" >&2
    exit 1
  else
    forwarded_status=$?
  fi
  [ "$forwarded_status" -eq 42 ]
  [ "$(< "$signal_forwarded")" = forwarded ]

  set +e
  "$launcher" /bin/sh -c 'kill -TERM $$'
  mirrored_status=$?
  set -e
  [ "$mirrored_status" -eq 143 ]

  swap_candidate="$PWD/swap-candidate"
  swap_target="$PWD/swap-target"
  ${pkgs.coreutils}/bin/mkdir -p "$swap_candidate" "$swap_target"
  printf new > "$swap_candidate/value"
  printf old > "$swap_target/value"
  "$atomic_replace" "$swap_candidate" "$swap_target"
  [ "$(< "$swap_target/value")" = new ]
  [ "$(< "$swap_candidate/value")" = old ]

  ${pkgs.coreutils}/bin/rm -rf "$swap_candidate" "$swap_target"
  ${pkgs.coreutils}/bin/mkdir -p "$swap_candidate"
  printf initial > "$swap_candidate/value"
  "$atomic_replace" "$swap_candidate" "$swap_target"
  [ ! -e "$swap_candidate" ]
  [ "$(< "$swap_target/value")" = initial ]

  touch "$out"
''
