{ pkgs }:
{
  packageOverrides = pkgs: import ~/.nixpkgs/overrides.nix { pkgs = pkgs; };

  allowUnfree = true;
  allowBroken = true;
}
