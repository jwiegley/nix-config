{
  lib,
  pkgs,
}:

{
  defaults ? { },
  keychainCommand ? "/usr/bin/security",
  keychainCredentials ? { },
  package,
  program,
}:

let
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
  credentialPrelude = lib.optionalString (keychainCredentials != { }) ''
    _nix_managed_restore_xtrace=0
    case "$-" in
      *x*) _nix_managed_restore_xtrace=1; set +x ;;
    esac
    ${credentialLookups}
    unset _nix_managed_credential
    if [[ "$_nix_managed_restore_xtrace" == 1 ]]; then
      unset _nix_managed_restore_xtrace
      set -x
    else
      unset _nix_managed_restore_xtrace
    fi
  '';
  defaultArguments = lib.concatStringsSep " " (
    lib.mapAttrsToList (
      name: value: "--set-default ${lib.escapeShellArg name} ${lib.escapeShellArg value}"
    ) defaults
  );
in
assert builtins.isString program && builtins.match "[A-Za-z0-9][A-Za-z0-9._+-]*" program != null;
assert
  builtins.isString keychainCommand
  && lib.hasPrefix "/" keychainCommand
  && keychainCommand != "/"
  && !lib.hasInfix "\n" keychainCommand
  && !lib.hasInfix "\r" keychainCommand;
assert builtins.all validEnvironmentName (builtins.attrNames defaults);
assert builtins.all validEnvironmentName (builtins.attrNames keychainCredentials);
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
      wrapProgram "$out/bin/"${lib.escapeShellArg program} ${defaultArguments} \
        --run ${lib.escapeShellArg credentialPrelude}
    '';
  }
  // lib.optionalAttrs (package ? pname) { inherit (package) pname; }
  // lib.optionalAttrs (package ? version) { inherit (package) version; }
)
