# Python AI package exposure.
_final: prev:

{
  pythonPackagesExtensions =
    (prev.pythonPackagesExtensions or [ ])
    ++ (import ../../packages/ai-python-extensions.nix { inherit prev; });
}
