#!/usr/bin/env python3
"""
Generate boilerplate Node-RED flows for common patterns.
Usage: python create_flow_template.py <template_type> [output.json]

Templates: mqtt, http-api, data-pipeline, error-handler
"""

import json
import secrets
import sys


def generate_id():
    """Generate Node-RED compatible ID (16 hex characters)."""
    return secrets.token_hex(8)


def create_mqtt_flow():
    """Create MQTT publish/subscribe template."""
    tab_id = generate_id()
    return [
        {
            "id": tab_id,
            "type": "tab",
            "label": "MQTT Flow",
            "disabled": False,
            "info": "MQTT publish and subscribe template",
        },
        {
            "id": generate_id(),
            "type": "mqtt in",
            "z": tab_id,
            "name": "Subscribe to Topic",
            "topic": "sensors/+/temperature",
            "qos": "2",
            "datatype": "json",
            "broker": "",
            "x": 130,
            "y": 100,
            "wires": [[]],
        },
        {
            "id": generate_id(),
            "type": "mqtt out",
            "z": tab_id,
            "name": "Publish to Topic",
            "topic": "control/device/command",
            "qos": "2",
            "retain": False,
            "broker": "",
            "x": 500,
            "y": 200,
            "wires": [],
        },
        {
            "id": generate_id(),
            "type": "comment",
            "z": tab_id,
            "name": "Configure MQTT Broker",
            "info": "Double-click MQTT nodes to configure broker connection",
            "x": 150,
            "y": 40,
            "wires": [],
        },
    ]


def create_http_api_flow():
    """Create HTTP REST API endpoint template."""
    tab_id = generate_id()
    http_in_id = generate_id()
    function_id = generate_id()
    http_resp_id = generate_id()

    return [
        {
            "id": tab_id,
            "type": "tab",
            "label": "REST API",
            "disabled": False,
            "info": "REST API endpoint template",
        },
        {
            "id": http_in_id,
            "type": "http in",
            "z": tab_id,
            "name": "API Endpoint",
            "url": "/api/v1/data",
            "method": "get",
            "upload": False,
            "swaggerDoc": "",
            "x": 120,
            "y": 100,
            "wires": [[function_id]],
        },
        {
            "id": function_id,
            "type": "function",
            "z": tab_id,
            "name": "Process Request",
            "func": (
                "// Access request data\n"
                "const query = msg.req.query;\n"
                "const headers = msg.req.headers;\n"
                "\n"
                "// Process the request\n"
                "let response = {\n"
                "    status: 'success',\n"
                "    timestamp: new Date().toISOString(),\n"
                "    data: {\n"
                "        // Add your data here\n"
                "    }\n"
                "};\n"
                "\n"
                "// Set response\n"
                "msg.payload = response;\n"
                "msg.statusCode = 200;\n"
                "msg.headers = {\n"
                "    'Content-Type': 'application/json'\n"
                "};\n"
                "\n"
                "return msg;"
            ),
            "outputs": 1,
            "noerr": 0,
            "initialize": "",
            "finalize": "",
            "libs": [],
            "x": 300,
            "y": 100,
            "wires": [[http_resp_id]],
        },
        {
            "id": http_resp_id,
            "type": "http response",
            "z": tab_id,
            "name": "Send Response",
            "statusCode": "",
            "headers": {},
            "x": 500,
            "y": 100,
            "wires": [],
        },
    ]


def create_data_pipeline_flow():
    """Create data processing pipeline template."""
    tab_id = generate_id()
    inject_id = generate_id()
    transform_id = generate_id()
    filter_id = generate_id()
    output_id = generate_id()

    return [
        {
            "id": tab_id,
            "type": "tab",
            "label": "Data Pipeline",
            "disabled": False,
            "info": "Data processing pipeline template",
        },
        {
            "id": inject_id,
            "type": "inject",
            "z": tab_id,
            "name": "Data Source",
            "props": [{"p": "payload"}, {"p": "topic", "vt": "str"}],
            "repeat": "60",
            "crontab": "",
            "once": False,
            "onceDelay": 0.1,
            "topic": "data",
            "payload": "[1,2,3,4,5]",
            "payloadType": "json",
            "x": 130,
            "y": 100,
            "wires": [[transform_id]],
        },
        {
            "id": transform_id,
            "type": "function",
            "z": tab_id,
            "name": "Transform Data",
            "func": (
                "// Transform array data\n"
                "if (Array.isArray(msg.payload)) {\n"
                "    msg.payload = msg.payload.map(item => ({\n"
                "        value: item,\n"
                "        timestamp: Date.now(),\n"
                "        processed: true\n"
                "    }));\n"
                "}\n"
                "\n"
                "return msg;"
            ),
            "outputs": 1,
            "noerr": 0,
            "initialize": "",
            "finalize": "",
            "x": 320,
            "y": 100,
            "wires": [[filter_id]],
        },
        {
            "id": filter_id,
            "type": "function",
            "z": tab_id,
            "name": "Filter Results",
            "func": (
                "// Filter processed data\n"
                "if (Array.isArray(msg.payload)) {\n"
                "    msg.payload = msg.payload.filter(item => \n"
                "        item.processed && item.value > 2\n"
                "    );\n"
                "}\n"
                "\n"
                "return msg;"
            ),
            "outputs": 1,
            "noerr": 0,
            "x": 510,
            "y": 100,
            "wires": [[output_id]],
        },
        {
            "id": output_id,
            "type": "debug",
            "z": tab_id,
            "name": "Pipeline Output",
            "active": True,
            "tosidebar": True,
            "console": False,
            "tostatus": False,
            "complete": "payload",
            "targetType": "msg",
            "statusVal": "",
            "statusType": "auto",
            "x": 700,
            "y": 100,
            "wires": [],
        },
    ]


def create_error_handler_flow():
    """Create error handling pattern template."""
    tab_id = generate_id()
    inject_id = generate_id()
    try_id = generate_id()
    catch_id = generate_id()
    log_id = generate_id()

    return [
        {
            "id": tab_id,
            "type": "tab",
            "label": "Error Handler",
            "disabled": False,
            "info": "Error handling pattern template",
        },
        {
            "id": inject_id,
            "type": "inject",
            "z": tab_id,
            "name": "Trigger",
            "props": [{"p": "payload"}],
            "repeat": "",
            "crontab": "",
            "once": False,
            "onceDelay": 0.1,
            "topic": "",
            "payload": "test",
            "payloadType": "str",
            "x": 110,
            "y": 100,
            "wires": [[try_id]],
        },
        {
            "id": try_id,
            "type": "function",
            "z": tab_id,
            "name": "Try Operation",
            "func": (
                "try {\n"
                "    // Simulate operation that might fail\n"
                "    if (Math.random() > 0.5) {\n"
                "        throw new Error('Random failure occurred');\n"
                "    }\n"
                "    \n"
                "    msg.payload = {\n"
                "        status: 'success',\n"
                "        result: 'Operation completed'\n"
                "    };\n"
                "    \n"
                "    return msg;\n"
                "} catch (error) {\n"
                "    // Trigger catch node\n"
                "    node.error(error.message, msg);\n"
                "    return null;\n"
                "}"
            ),
            "outputs": 1,
            "noerr": 0,
            "initialize": "",
            "finalize": "",
            "x": 280,
            "y": 100,
            "wires": [[]],
        },
        {
            "id": catch_id,
            "type": "catch",
            "z": tab_id,
            "name": "Catch Errors",
            "scope": [try_id],
            "uncaught": False,
            "x": 110,
            "y": 200,
            "wires": [[log_id]],
        },
        {
            "id": log_id,
            "type": "function",
            "z": tab_id,
            "name": "Log & Recover",
            "func": (
                "// Log error details\n"
                "const errorDetails = {\n"
                "    timestamp: new Date().toISOString(),\n"
                "    error: msg.error.message,\n"
                "    source: msg.error.source.name || msg.error.source.id,\n"
                "    original_payload: msg.payload\n"
                "};\n"
                "\n"
                "node.warn('Error caught: ' + JSON.stringify(errorDetails));\n"
                "\n"
                "// Attempt recovery or send alert\n"
                "msg.payload = {\n"
                "    status: 'error',\n"
                "    details: errorDetails,\n"
                "    recovery: 'Attempting fallback operation...'\n"
                "};\n"
                "\n"
                "return msg;"
            ),
            "outputs": 1,
            "noerr": 0,
            "x": 300,
            "y": 200,
            "wires": [[]],
        },
    ]


TEMPLATES = {
    "mqtt": create_mqtt_flow,
    "http-api": create_http_api_flow,
    "data-pipeline": create_data_pipeline_flow,
    "error-handler": create_error_handler_flow,
}


def main():
    if len(sys.argv) < 2:
        print("Usage: python create_flow_template.py <template_type> [output.json]")
        print(f"Available templates: {', '.join(TEMPLATES.keys())}")
        sys.exit(1)

    template_type = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else f"{template_type}-flow.json"

    if template_type not in TEMPLATES:
        print(f"Unknown template: {template_type}")
        print(f"Available templates: {', '.join(TEMPLATES.keys())}")
        sys.exit(1)

    flow = TEMPLATES[template_type]()

    with open(output_file, "w") as f:
        json.dump(flow, f, indent=2)

    print(f"✓ Created {template_type} flow template: {output_file}")
    print(f"  {len(flow)} nodes generated")


if __name__ == "__main__":
    main()
