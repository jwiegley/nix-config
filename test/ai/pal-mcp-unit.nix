{
  palMcpServer,
  pkgs,
}:
let
  python = pkgs.python3.withPackages (
    ps: with ps; [
      anthropic
      droid-sdk
      google-genai
      mcp
      openai
      pydantic
      pytest
      pytest-asyncio
      python-dotenv
    ]
  );
in
pkgs.runCommand "pal-mcp-unit"
  {
    nativeBuildInputs = [ python ];
  }
  ''
    cp -R ${palMcpServer}/. source
    chmod -R u+w source
    cd source
    export HOME=$TMPDIR/home
    export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    export PAL_MCP_FORCE_ENV_OVERRIDE=false
    export SSL_CERT_FILE=$NIX_SSL_CERT_FILE
    mkdir -p "$HOME"
    ${python}/bin/python3 -m pytest -m 'not integration' tests
    touch "$out"
  ''
