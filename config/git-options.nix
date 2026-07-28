# Option surface for the shared git configuration.
#
# This is a separate module from config/git.nix for a module-system reason, not a
# stylistic one: a module that declares a top-level `options` attribute must move
# every other top-level attribute under an explicit `config`. config/git.nix is
# 346 lines of plain configuration, and wrapping all of it would produce a
# whole-file reindent whose diff hides the change being made. Declaring the
# option here keeps both files readable.
#
# Refs: jwiegley/nix-config#35.
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

        Set this instead of overriding the individual settings.

        Before this option existed the package was string-interpolated directly
        into roughly a dozen option *values* — git aliases, the media
        clean/smudge filters, the zsh bisect helpers. That made "use a different
        git" impossible to express as a choice: a consumer had to `mkForce` each
        interpolated string one at a time, which is a large part of why the vps
        configuration accumulated 35 `mkForce` and vulcan carried shims.

        The default reproduces the previous expression exactly, including the
        git-ai selection in `config/vars.nix`, so leaving it alone changes
        nothing that is realized.
      '';
    };
  };
}
