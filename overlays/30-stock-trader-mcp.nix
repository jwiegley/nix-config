final: prev:

prev.lib.optionalAttrs (prev ? inputs && prev.inputs ? stock-trader) {
  stock-trader-mcp =
    let
      pyEnv = final.python3.withPackages (ps: [
        ps.mcp
        ps.requests
      ]);
      script = final.writeText "stock-trader-mcp.py" (
        builtins.readFile "${prev.inputs.stock-trader}/scripts/stock-trader-mcp.py"
      );
      caBundle =
        if prev ? ca-bundle-with-vulcan then
          "${prev.ca-bundle-with-vulcan}/etc/ssl/certs/ca-bundle.crt"
        else
          "${prev.cacert}/etc/ssl/certs/ca-bundle.crt";
    in
    final.writeShellApplication {
      name = "stock-trader-mcp";
      runtimeInputs = [ pyEnv ];
      text = ''
        export REQUESTS_CA_BUNDLE="''${REQUESTS_CA_BUNDLE:-${caBundle}}"
        export STOCK_TRADER_BASE_URL="''${STOCK_TRADER_BASE_URL:-https://trader.vulcan.lan}"
        exec python3 "${script}" "$@"
      '';
    };
}
