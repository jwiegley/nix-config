# Ledger CLI accounting from an explicitly supplied flake input.
{
  ledger ? null,
}:
_final: prev:

prev.lib.optionalAttrs (ledger != null) {
  ledger_HEAD = ledger.packages.${prev.stdenv.hostPlatform.system}.ledger.overrideAttrs (_attrs: {
    boost = prev.boost.override { python = prev.python3; };
  });
}
