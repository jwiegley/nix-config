{
  config,
  lib,
  pkgs,
  vars,
  ...
}:

let
  cfg = config.johnw.hermesAgent;
  serviceEnabled = config.johnw.host.isHera && config.services.hermes-agent.enable;
  runtimePackage =
    if cfg.runtimePackage != null then
      cfg.runtimePackage
    else
      pkgs.runCommand "missing-hermes-runtime-package" { } ''
        mkdir -p "$out/bin"
      '';
  homeDirectory = config.home.homeDirectory;
  hermesHome = config.services.hermes-agent.hermesHome;
  logDirectory = "${hermesHome}/logs";
  launcher = pkgs.callPackage ./hermes-agent-service-launcher.nix { };
  operatorPackage = pkgs.callPackage ../packages/hermes-agent-ops.nix { };
  launcherApp = "${launcher}/${launcher.appRelativePath}";
  atomicReplace = "${launcher}/${launcher.atomicReplaceRelativePath}";
  fixedApp = "${homeDirectory}/Applications/${launcher.bundleName}.app";
  fixedExecutable = "${fixedApp}/Contents/MacOS/${launcher.executableName}";
  signingIdentity = "Apple Development: jwiegley@gmail.com (Y546N259NB)";
  signingRequirement = ''identifier "${launcher.bundleIdentifier}" and anchor apple generic and certificate leaf[subject.OU] = "Y546N259NB" and certificate leaf[subject.CN] = "${signingIdentity}"'';
  runtimePath = lib.concatStringsSep ":" [
    "${homeDirectory}/src/scripts"
    "${config.home.profileDirectory}/bin"
    "${homeDirectory}/.local/bin"
    "${homeDirectory}/work/positron/bin"
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

  serviceEntry = pkgs.writeShellScriptBin "hermes" ''
    exec ${lib.escapeShellArg fixedExecutable} \
      ${lib.escapeShellArg "${runtimePackage}/bin/hermes"} "$@"
  '';
  servicePackage = pkgs.symlinkJoin {
    name = "hermes-agent-service";
    paths = [ runtimePackage ];
    postBuild = ''
      rm "$out/bin/hermes"
      ln -s ${serviceEntry}/bin/hermes "$out/bin/hermes"
    '';
    passthru = {
      hermesAgentRuntimePackage = runtimePackage;
      hermesAgentServiceEntry = serviceEntry;
      hermesAgentServiceLauncher = launcher;
    };
  };
in
{
  options.johnw.hermesAgent.runtimePackage = lib.mkOption {
    type = lib.types.nullOr lib.types.package;
    default = null;
    description = ''
      The credential-injecting Hermes package used behind Hera's signed native
      service launcher. This stays separate from services.hermes-agent.package,
      which is the service-facing package installed by the upstream module.
    '';
  };

  config = lib.mkIf serviceEnabled {
    home.packages = [ operatorPackage ];

    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "Hera's Hermes Agent service requires Darwin";
      }
      {
        assertion = cfg.runtimePackage != null;
        message = "Hera's Hermes Agent service requires johnw.hermesAgent.runtimePackage";
      }
      {
        assertion = config.services.hermes-agent.gateway.enable;
        message = "Hera's native Hermes Agent service requires the upstream gateway";
      }
      {
        assertion = config.services.hermes-agent.backend.mode == "none";
        message = "Hera uses the upstream Hermes gateway as its only launchd job";
      }
    ];

    services.hermes-agent = {
      package = servicePackage;
    };

    # Install the store artifact into its stable TCC identity, re-sign it with
    # the one reviewed login-Keychain identity, verify that exact identity, and
    # only then replace the live app in one filesystem operation.
    home.activation.installHermesAgentServiceApp =
      lib.hm.dag.entryBetween
        [ "setupLaunchAgents" ]
        [
          "linkGeneration"
          "hermesAgentSetup"
        ]
        ''
          if [[ ! -v DRY_RUN ]]; then
            app_parent=${lib.escapeShellArg "${homeDirectory}/Applications"}
            app_source=${lib.escapeShellArg launcherApp}
            app_target=${lib.escapeShellArg fixedApp}
            signing_identity=${lib.escapeShellArg signingIdentity}
            signing_requirement=${lib.escapeShellArg signingRequirement}

            /bin/mkdir -p "$app_parent"
            ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg logDirectory}

            if [[ -e "$app_target" || -L "$app_target" ]]; then
              if [[ ! -d "$app_target" || -L "$app_target" ]]; then
                echo "Hermes Agent service app target is not a directory" >&2
                exit 1
              fi
            fi

            identities="$(/usr/bin/security find-identity -v -p codesigning)" || {
              echo "Could not inspect the login Keychain codesigning identities" >&2
              exit 1
            }
            signer_hashes="$(
              printf '%s\n' "$identities" \
                | /usr/bin/awk -v identity="$signing_identity" \
                    'index($0, "\"" identity "\"") { print $2 }'
            )"
            if [[ -z "$signer_hashes" || "$signer_hashes" == *$'\n'* ]]; then
              echo "Expected exactly one valid codesigning identity named: $signing_identity" >&2
              exit 1
            fi
            if [[ ! "$signer_hashes" =~ ^[[:xdigit:]]{40}$ ]]; then
              echo "The selected Hermes Agent codesigning identity has an invalid fingerprint" >&2
              exit 1
            fi

            candidate_root=
            cleanup_candidate() {
              if [[ -n "$candidate_root" ]]; then
                /bin/rm -rf "$candidate_root"
              fi
            }
            terminate_candidate() {
              signal_status="$1"
              cleanup_candidate
              trap - EXIT HUP INT TERM
              exit "$signal_status"
            }
            trap cleanup_candidate EXIT
            trap 'terminate_candidate 129' HUP
            trap 'terminate_candidate 130' INT
            trap 'terminate_candidate 143' TERM

            candidate_root="$(/usr/bin/mktemp -d "$app_parent/.hermes-agent-service.XXXXXX")"
            candidate="$candidate_root/${launcher.bundleName}.app"

            /usr/bin/ditto --rsrc --extattr "$app_source" "$candidate"
            /bin/chmod -R u+rwX,go-w "$candidate"
            [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$candidate/Contents/Info.plist")" == \
              ${lib.escapeShellArg launcher.bundleIdentifier} ]]
            [[ "$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$candidate/Contents/Info.plist")" == \
              ${lib.escapeShellArg launcher.executableName} ]]
            [[ "$(/usr/bin/plutil -extract LSBackgroundOnly raw -o - "$candidate/Contents/Info.plist")" == true ]]

            /usr/bin/codesign --force --sign "$signer_hashes" \
              --identifier ${lib.escapeShellArg launcher.bundleIdentifier} \
              --options runtime --timestamp=none "$candidate"
            /usr/bin/codesign --verify --strict --verbose=4 \
              -R="$signing_requirement" "$candidate"

            ${atomicReplace} "$candidate" "$app_target"
            if [[ -e "$candidate" ]]; then
              /bin/chmod -R u+rwX "$candidate"
            fi
            /bin/rm -rf "$candidate_root"
            candidate_root=
            trap - EXIT HUP INT TERM
          fi
        '';

    launchd.agents.hermes-agent.config = {
      AssociatedBundleIdentifiers = [ launcher.bundleIdentifier ];
      ProcessType = lib.mkForce "Standard";
      StandardOutPath = lib.mkForce "${logDirectory}/gateway.log";
      StandardErrorPath = lib.mkForce "${logDirectory}/gateway.err.log";
      Umask = 63;
      EnvironmentVariables = {
        HOME = homeDirectory;
        USER = config.home.username;
        LOGNAME = config.home.username;
        PATH = lib.mkForce runtimePath;
        XDG_CONFIG_HOME = config.xdg.configHome;
        XDG_DATA_HOME = config.xdg.dataHome;
        XDG_STATE_HOME = config.xdg.stateHome;
        GNUPGHOME = "${config.xdg.configHome}/gnupg";
        SSH_AUTH_SOCK = "${config.xdg.configHome}/gnupg/S.gpg-agent.ssh";
        SSL_CERT_FILE = vars.ca-bundle_crt;
        NIX_CONFIG = "max-jobs = 1\ncores = 8";
        HTTP_PROXY = "";
        HTTPS_PROXY = "";
        ALL_PROXY = "";
        NO_PROXY = "*";
        http_proxy = "";
        https_proxy = "";
        all_proxy = "";
        no_proxy = "*";
      };
    };
  };
}
