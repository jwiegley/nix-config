import json
import os
import sys

FORBIDDEN_ENVIRONMENT = (
    "ANTHROPIC_API_KEY",
    "BASH_ENV",
    "DISABLE_AUTOUPDATER",
    "DISABLE_INSTALLATION_CHECKS",
    "DISABLE_NON_ESSENTIAL_MODEL_CALLS",
    "DYLD_INSERT_LIBRARIES",
    "FACTORY_AIRGAP_ENABLED",
    "FACTORY_DISABLE_DYNAMIC_CONFIG",
    "FACTORY_DROID_AUTO_UPDATE_ENABLED",
    "FACTORY_MCP_BLOCKING_LOAD_TIMEOUT_MS",
    "FACTORY_API_KEY",
    "FACTORY_OTEL_ENABLED",
    "GEMINI_API_KEY",
    "XAI_API_KEY",
    "GIT_AI_SOCKET",
    "GIT_TRACE2_EVENT",
    "LD_PRELOAD",
    "NODE_OPTIONS",
    "PYTHONPATH",
    "SSH_AUTH_SOCK",
    "TASK3_NETWORK_ATTEMPT_FILE",
    "TASK3_NETWORK_GUARD_LOADED_FILE",
    "UNRELATED_SECRET",
)


def main() -> None:
    if len(sys.argv) not in (2, 5):
        raise AssertionError("managed MCP probe requires its expected PATH")
    droid_mode = len(sys.argv) == 5 and sys.argv[2] == "droid"
    if len(sys.argv) == 5 and not droid_mode:
        raise AssertionError("managed MCP probe received an unknown mode")
    if os.environ.get("OPENAI_API_KEY") != "typed-sentinel":
        raise AssertionError("managed MCP lost its declared typed environment")
    if droid_mode and os.environ.get("GEMINI_API_KEY") != "droid-gemini-sentinel":
        raise AssertionError("managed MCP lost Droid's Gemini environment")
    if os.environ.get("DEFAULT_MODEL") != "auto":
        raise AssertionError("managed MCP lost its declared literal environment")
    if os.environ.get("PATH") != sys.argv[1]:
        raise AssertionError("managed MCP did not receive its immutable PATH")
    if os.environ.get("NIX_SSL_CERT_FILE") != "/managed-ca":
        raise AssertionError("managed MCP lost its declared CA authority")
    if droid_mode:
        expected_platform = {
            "HOME": sys.argv[3],
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "LOGNAME": "test",
            "NIX_SSL_CERT_FILE": "/managed-ca",
            "SHELL": "/managed-shell",
            "SSL_CERT_FILE": "/managed-ssl",
            "TERM": "dumb",
            "TMPDIR": sys.argv[4],
            "USER": "test",
            "XDG_CONFIG_HOME": f"{sys.argv[3]}/.config",
        }
        for name, expected in expected_platform.items():
            if os.environ.get(name) != expected:
                raise AssertionError(f"managed MCP lost Droid platform name {name}")
        if "NODE_EXTRA_CA_CERTS" in os.environ:
            raise AssertionError("managed MCP fabricated an absent Droid CA name")
    forbidden_environment = set(FORBIDDEN_ENVIRONMENT)
    if droid_mode:
        forbidden_environment.remove("GEMINI_API_KEY")
    present = [name for name in forbidden_environment if name in os.environ]
    if present:
        raise AssertionError(f"managed MCP inherited forbidden names: {present}")

    for line in sys.stdin:
        request = json.loads(line)
        request_id = request.get("id")
        if request_id is None:
            continue
        method = request.get("method")
        if method == "initialize":
            result = {
                "protocolVersion": "2025-06-18",
                "capabilities": {"tools": {}},
                "serverInfo": {
                    "name": "nix-managed-environment-probe",
                    "version": "1",
                },
            }
        elif method == "tools/list":
            result = {
                "tools": [
                    {
                        "name": "environment_ok",
                        "description": "The managed environment is isolated.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {"value": {"type": "string"}},
                            "required": ["value"],
                            "additionalProperties": False,
                        },
                    }
                ]
            }
        elif method == "tools/call":
            params = request.get("params", {})
            arguments = params.get("arguments", {})
            value = arguments.get("value")
            if params.get("name") != "environment_ok" or not isinstance(value, str):
                raise AssertionError("managed MCP received an invalid synthetic call")
            result = {"content": [{"type": "text", "text": f"synthetic-mcp:{value}"}]}
        elif method == "ping":
            result = {}
        else:
            response = {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {"code": -32601, "message": "Method not found"},
            }
            print(json.dumps(response, separators=(",", ":")), flush=True)
            continue
        response = {"jsonrpc": "2.0", "id": request_id, "result": result}
        print(json.dumps(response, separators=(",", ":")), flush=True)
        if droid_mode and method == "initialize":
            return


if __name__ == "__main__":
    main()
