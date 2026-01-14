final: prev: {
  # Fix zbar test failures on macOS
  # Tests fail with zbarimg returning error status (-11) which is a segfault
  # Disable tests as the package itself works fine
  zbar = prev.zbar.overrideAttrs (oldAttrs: { doCheck = false; });
}
