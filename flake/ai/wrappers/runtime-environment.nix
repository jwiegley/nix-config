{
  lib,
  pkgs,
}:

{
  defaults ? { },
  keychainCommand ? "/usr/bin/security",
  keychainCredentials ? { },
  package,
  program ? null,
  programs ? null,
  requiredKeychainCredentials ? [ ],
}:

let
  wrappedPrograms = if programs == null then [ program ] else programs;
  validEnvironmentName = name: builtins.match "[A-Z][A-Z0-9_]*" name != null;
  validMetadata =
    value:
    builtins.isAttrs value
    &&
      builtins.attrNames value == [
        "account"
        "service"
      ]
    &&
      builtins.all
        (
          field:
          builtins.isString value.${field}
          && value.${field} != ""
          && !lib.hasInfix "\n" value.${field}
          && !lib.hasInfix "\r" value.${field}
        )
        [
          "account"
          "service"
        ];
  credentialLookups = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (environmentName: metadata: ''
      if [[ -z "''${${environmentName}+x}" ]]; then
        if _nix_managed_credential=$(
          ${lib.escapeShellArg keychainCommand} find-generic-password \
            -s ${lib.escapeShellArg metadata.service} \
            -a ${lib.escapeShellArg metadata.account} \
            -w 2>/dev/null
        ); then
          export ${environmentName}="$_nix_managed_credential"
        else
          unset ${environmentName}
        fi
      fi
    '') keychainCredentials
  );
  requiredCredentialResets = lib.concatMapStringsSep "\n" (
    environmentName: "unset ${environmentName}"
  ) requiredKeychainCredentials;
  credentialPrelude = lib.optionalString (keychainCredentials != { }) ''
    case "$-" in
      *a*) set +a; _nix_managed_restore_allexport=1 ;;
      *) _nix_managed_restore_allexport=0 ;;
    esac
    _nix_managed_restore_xtrace=0
    case "$-" in
      *x*) _nix_managed_restore_xtrace=1; set +x ;;
    esac
    unset _nix_managed_credential
    ${requiredCredentialResets}
    ${credentialLookups}
    unset _nix_managed_credential
    ${lib.concatMapStringsSep "\n" (environmentName: ''
      if [[ -z "''${${environmentName}:-}" ]]; then
        printf '%s\n' ${lib.escapeShellArg "required runtime credential ${environmentName} is unavailable"} >&2
        exit 78
      fi
    '') requiredKeychainCredentials}
    if [[ "$_nix_managed_restore_allexport" == 1 ]]; then
      if [[ "$_nix_managed_restore_xtrace" == 1 ]]; then
        unset _nix_managed_restore_allexport _nix_managed_restore_xtrace
        set -a
        set -x
      else
        unset _nix_managed_restore_allexport _nix_managed_restore_xtrace
        set -a
      fi
    elif [[ "$_nix_managed_restore_xtrace" == 1 ]]; then
      unset _nix_managed_restore_allexport _nix_managed_restore_xtrace
      set -x
    else
      unset _nix_managed_restore_allexport _nix_managed_restore_xtrace
    fi
  '';
  defaultArguments = lib.concatStringsSep " " (
    lib.mapAttrsToList (
      name: value: "--set-default ${lib.escapeShellArg name} ${lib.escapeShellArg value}"
    ) defaults
  );
in
assert (program == null) != (programs == null);
assert builtins.isList wrappedPrograms && wrappedPrograms != [ ];
assert builtins.length wrappedPrograms == builtins.length (lib.unique wrappedPrograms);
assert builtins.all (
  name: builtins.isString name && builtins.match "[A-Za-z0-9][A-Za-z0-9._+-]*" name != null
) wrappedPrograms;
assert
  builtins.isString keychainCommand
  && lib.hasPrefix "/" keychainCommand
  && keychainCommand != "/"
  && !lib.hasInfix "\n" keychainCommand
  && !lib.hasInfix "\r" keychainCommand;
assert builtins.all validEnvironmentName (builtins.attrNames defaults);
assert builtins.all validEnvironmentName (builtins.attrNames keychainCredentials);
assert builtins.isList requiredKeychainCredentials;
assert
  builtins.length requiredKeychainCredentials
  == builtins.length (lib.unique requiredKeychainCredentials);
assert builtins.all validEnvironmentName requiredKeychainCredentials;
assert builtins.all (name: builtins.hasAttr name keychainCredentials) requiredKeychainCredentials;
assert
  lib.intersectLists (builtins.attrNames defaults) (builtins.attrNames keychainCredentials) == [ ];
assert builtins.all validMetadata (builtins.attrValues keychainCredentials);
pkgs.symlinkJoin (
  {
    inherit (package) name;
    meta = package.meta or { };
    passthru = package.passthru or { };
    paths = [ package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for program in ${lib.escapeShellArgs wrappedPrograms}; do
        wrapProgram "$out/bin/$program" ${defaultArguments} \
          --run ${lib.escapeShellArg credentialPrelude}
      done
    '';
  }
  // lib.optionalAttrs (package ? pname) { inherit (package) pname; }
  // lib.optionalAttrs (package ? version) { inherit (package) version; }
)
