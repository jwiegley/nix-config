{
  configured,
  darwinConfigurations,
  lib,
  runCommand,
}:

let
  configuredHeadEnv = configured.emacsHEADEnv (_: [ ]);
  homePackageNames =
    configuration: map lib.getName configuration.config.home-manager.users.johnw.home.packages;
in
assert configured.emacsHEAD.version != "";
assert configured.emacsHEAD.drvPath != "";
assert configured.emacsHEADPackages.emacs.drvPath == configured.emacsHEAD.drvPath;
assert configured.emacsHEADPackagesNg.emacs.drvPath == configured.emacsHEAD.drvPath;
assert configuredHeadEnv.drvPath != "";
assert lib.getName configuredHeadEnv == "env-emacsHEAD";
assert builtins.all (
  configuration:
  let
    names = homePackageNames configuration;
  in
  builtins.elem "env-emacs30MacPort" names && !(builtins.elem "env-emacsHEAD" names)
) (builtins.attrValues darwinConfigurations);
runCommand "emacs-head-evaluation" { } "touch $out"
