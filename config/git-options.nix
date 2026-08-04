# Declare the shared Git package option separately so config/git.nix can remain
# a plain configuration module.
{ lib, vars, ... }:

{
  options.johnw.git = {
    package = lib.mkOption {
      type = lib.types.package;
      default = vars.gitPkg;
      defaultText = lib.literalExpression "vars.gitPkg";
      description = ''
        The git package every git setting and zsh alias is derived from.
        Consumed by `config/git.nix` and `config/zsh.nix`.

        Override this option instead of forcing individual Git-backed settings.
      '';
    };
  };
}
