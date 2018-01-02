{ pkgs }:
{
  packageOverrides = pkgs: import ./overrides.nix { pkgs = pkgs; };

  allowUnfree = true;
  allowBroken = true;
}
