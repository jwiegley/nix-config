{
  darwinConfigurations,
  homeConfigurations,
  nixosHomeEvaluationFixtures,
  pkgs,
}:

let
  inherit (pkgs) lib;
  desktopHomes = map (configuration: configuration.config.home-manager.users.johnw) (
    builtins.attrValues darwinConfigurations
  );
  sharedWork = homeConfigurations."jwiegley@x86_64-linux".config;
  nonDesktopHomes =
    map (fixture: fixture.config) (builtins.attrValues nixosHomeEvaluationFixtures)
    ++ map (configuration: configuration.config) (builtins.attrValues homeConfigurations);
  allHomes = desktopHomes ++ nonDesktopHomes;
  hasPackage = name: config: builtins.elem name (map lib.getName config.home.packages);
in
assert
  sharedWork.programs.zsh.history.path == "${sharedWork.xdg.configHome}/zsh/history-\${HOST%%.*}";
assert !sharedWork.programs.zsh.history.share;
assert builtins.elem "INC_APPEND_HISTORY" sharedWork.programs.zsh.setOptions;
assert builtins.all (config: builtins.hasAttr ".pi" config.home.file) allHomes;
assert builtins.all (
  config: builtins.hasAttr ".config/pi/agent/models.json" config.home.file
) allHomes;
assert builtins.all (
  config: config.home.activation.aiManagedPiBlackholePolicy.after == [ "linkGeneration" ]
) allHomes;
assert builtins.all (hasPackage "unisessions") allHomes;
assert builtins.all (
  config:
  config.programs.gpg.enable
  && config.programs.password-store.enable
  && builtins.hasAttr ".emacs.d" config.home.file
  && builtins.hasAttr ".gnupg" config.home.file
) desktopHomes;
assert builtins.all (
  config:
  !config.programs.gpg.enable
  && !config.programs.password-store.enable
  && !(builtins.hasAttr ".emacs.d" config.home.file)
  && !(builtins.hasAttr ".gnupg" config.home.file)
) nonDesktopHomes;
pkgs.runCommand "host-behavior" { } "touch $out"
