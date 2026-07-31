# Node-RED Node Schemas Reference

## Core Node Types

### inject
Triggers flows manually or on a schedule.

```json
{
  "id": "unique-id",
  "type": "inject",
  "z": "tab-id",
  "name": "Node Name",
  "props": [
    {"p": "payload"},
    {"p": "topic", "vt": "str"}
  ],
  "repeat": "",           // Seconds between repeats (empty = no repeat)
  "crontab": "",         // Cron expression (e.g., "0 0 * * *")
  "once": false,         // Trigger on deploy
  "onceDelay": 0.1,      // Seconds delay if once=true
  "topic": "",           // Topic string
  "payload": "",         // Payload content
  "payloadType": "str",  // str|num|bool|json|bin|date|env|flow|global
  "x": 100,
  "y": 100,
  "wires": [[]]
}
```

### function
Execute JavaScript code with access to message and context.

```json
{
  "id": "unique-id",
  "type": "function",
  "z": "tab-id",
  "name": "Process Data",
  "func": "// JavaScript code\nreturn msg;",
  "outputs": 1,          // Number of outputs
  "noerr": 0,           // 0=show errors, 1=hide
  "initialize": "",      // Setup code (run on deploy)
  "finalize": "",       // Cleanup code (run on close)
  "libs": [],           // External libraries
  "x": 300,
  "y": 100,
  "wires": [[]]
}
```

### debug
Output messages to debug sidebar or console.

```json
{
  "id": "unique-id",
  "type": "debug",
  "z": "tab-id",
  "name": "Debug Output",
  "active": true,        // Enable/disable output
  "tosidebar": true,     // Show in debug sidebar
  "console": false,      // Log to system console
  "tostatus": false,     // Show as node status
  "complete": "payload", // What to output
  "targetType": "msg",   // msg|full
  "statusVal": "",
  "statusType": "auto",
  "x": 500,
  "y": 100,
  "wires": []
}
```

### change
Set, change, delete, or move message properties.

```json
{
  "id": "unique-id",
  "type": "change",
  "z": "tab-id",
  "name": "Set Properties",
  "rules": [
    {
      "t": "set",      // set|change|delete|move
      "p": "payload",  // Property path
      "pt": "msg",     // msg|flow|global
      "to": "value",   // Target value
      "tot": "str"     // str|num|bool|json|bin|date|env|msg|flow|global
    }
  ],
  "action": "",
  "property": "",
  "from": "",
  "to": "",
  "reg": false,        // Use regex
  "x": 300,
  "y": 100,
  "wires": [[]]
}
```

### switch
Route messages based on property values.

```json
{
  "id": "unique-id",
  "type": "switch",
  "z": "tab-id",
  "name": "Route Messages",
  "property": "payload",
  "propertyType": "msg",
  "rules": [
    {"t": "eq", "v": "value1", "vt": "str"},
    {"t": "lt", "v": "10", "vt": "num"},
    {"t": "cont", "v": "text", "vt": "str"}
  ],
  "checkall": "true",    // Check all rules
  "repair": false,
  "outputs": 2,          // Number of outputs (matches rules)
  "x": 300,
  "y": 100,
  "wires": [[], []]
}
```

### delay
Delay or rate limit messages.

```json
{
  "id": "unique-id",
  "type": "delay",
  "z": "tab-id",
  "name": "Rate Limit",
  "pauseType": "rate",   // delay|rate|queue|random
  "timeout": "5",
  "timeoutUnits": "seconds",
  "rate": "1",
  "nbRateUnits": "1",
  "rateUnits": "second",
  "randomFirst": "1",
  "randomLast": "5",
  "randomUnits": "seconds",
  "drop": false,         // Drop intermediate messages
  "x": 300,
  "y": 100,
  "wires": [[]]
}
```

## Network Nodes

### http in
Create HTTP endpoint.

```json
{
  "id": "unique-id",
  "type": "http in",
  "z": "tab-id",
  "name": "API Endpoint",
  "url": "/api/endpoint",
  "method": "get",       // get|post|put|delete|patch
  "upload": false,       // Accept file uploads
  "swaggerDoc": "",      // OpenAPI documentation
  "x": 100,
  "y": 100,
  "wires": [[]]
}
```

### http response
Send HTTP response.

```json
{
  "id": "unique-id",
  "type": "http response",
  "z": "tab-id",
  "name": "Send Response",
  "statusCode": "",      // Override status code
  "headers": {},         // Custom headers
  "x": 500,
  "y": 100,
  "wires": []
}
```

### http request
Make HTTP requests.

```json
{
  "id": "unique-id",
  "type": "http request",
  "z": "tab-id",
  "name": "API Call",
  "method": "GET",       // GET|POST|PUT|DELETE|use msg.method
  "ret": "txt",         // txt|bin|obj
  "paytoqs": "ignore",  // ignore|query|body
  "url": "https://api.example.com",
  "tls": "",            // TLS config node ID
  "persist": false,     // Keep connection alive
  "proxy": "",          // Proxy config node ID
  "authType": "",       // basic|bearer
  "x": 300,
  "y": 100,
  "wires": [[]]
}
```

### mqtt in
Subscribe to MQTT topics.

```json
{
  "id": "unique-id",
  "type": "mqtt in",
  "z": "tab-id",
  "name": "MQTT Subscribe",
  "topic": "sensors/+/temperature",
  "qos": "2",           // 0|1|2
  "datatype": "auto",   // auto|json|utf8|base64
  "broker": "broker-config-id",
  "nl": false,          // Remove newlines
  "rap": true,          // Report as parsed
  "rh": 0,              // Retain handling
  "x": 100,
  "y": 100,
  "wires": [[]]
}
```

### mqtt out
Publish to MQTT topics.

```json
{
  "id": "unique-id",
  "type": "mqtt out",
  "z": "tab-id",
  "name": "MQTT Publish",
  "topic": "",          // Can use msg.topic
  "qos": "",           // 0|1|2 or use msg.qos
  "retain": "",        // true|false or use msg.retain
  "respTopic": "",     // Response topic
  "contentType": "",   // MQTT 5.0 content type
  "userProps": "",     // MQTT 5.0 user properties
  "correl": "",        // MQTT 5.0 correlation data
  "expiry": "",        // MQTT 5.0 message expiry
  "broker": "broker-config-id",
  "x": 500,
  "y": 100,
  "wires": []
}
```

### websocket in/out
WebSocket communication nodes.

```json
{
  "id": "unique-id",
  "type": "websocket in",
  "z": "tab-id",
  "name": "WS Receive",
  "server": "",         // Server config ID
  "client": "client-config-id",
  "x": 100,
  "y": 100,
  "wires": [[]]
}
```

## Storage Nodes

### file in
Read file from filesystem.

```json
{
  "id": "unique-id",
  "type": "file in",
  "z": "tab-id",
  "name": "Read File",
  "filename": "/path/to/file",
  "format": "utf8",     // utf8|lines|stream|base64
  "chunk": false,       // Stream in chunks
  "sendError": false,   // Send errors to catch node
  "encoding": "none",   // Encoding for legacy
  "x": 300,
  "y": 100,
  "wires": [[]]
}
```

### file
Write file to filesystem.

```json
{
  "id": "unique-id",
  "type": "file",
  "z": "tab-id",
  "name": "Write File",
  "filename": "/path/to/file",
  "appendNewline": true,
  "createDir": false,   // Create directory if missing
  "overwriteFile": "true", // true|false|delete
  "encoding": "none",
  "x": 500,
  "y": 100,
  "wires": [[]]
}
```

## Logic Nodes

### range
Map numeric ranges.

```json
{
  "id": "unique-id",
  "type": "range",
  "z": "tab-id",
  "name": "Scale Values",
  "minin": "0",
  "maxin": "100",
  "minout": "0",
  "maxout": "1",
  "action": "scale",    // scale|clamp|roll
  "round": false,       // Round to integer
  "property": "payload",
  "x": 300,
  "y": 100,
  "wires": [[]]
}
```

### template
Apply Mustache template.

```json
{
  "id": "unique-id",
  "type": "template",
  "z": "tab-id",
  "name": "Format Output",
  "field": "payload",
  "fieldType": "msg",
  "format": "handlebars",  // handlebars|mustache|html|json|yaml|text
  "syntax": "mustache",
  "template": "Hello {{payload}}!",
  "output": "str",         // str|json|yaml
  "x": 300,
  "y": 100,
  "wires": [[]]
}
```

### join
Join message sequences.

```json
{
  "id": "unique-id",
  "type": "join",
  "z": "tab-id",
  "name": "Combine Messages",
  "mode": "auto",        // auto|custom
  "build": "object",     // object|array|string|buffer
  "property": "payload",
  "propertyType": "msg",
  "key": "topic",
  "joiner": "\\n",
  "joinerType": "str",
  "accumulate": false,
  "timeout": "",
  "count": "",
  "reduceRight": false,
  "reduceExp": "",
  "reduceInit": "",
  "reduceInitType": "",
  "reduceFixup": "",
  "x": 400,
  "y": 100,
  "wires": [[]]
}
```

### split
Split messages into sequences.

```json
{
  "id": "unique-id",
  "type": "split",
  "z": "tab-id",
  "name": "Split Array",
  "splt": "\\n",        // Split character
  "spltType": "str",    // str|bin|len
  "arraySplt": 1,       // Array split length
  "arraySpltType": "len",
  "stream": false,      // Handle as stream
  "addname": "",        // Add property name
  "x": 300,
  "y": 100,
  "wires": [[]]
}
```

## Error Handling

### catch
Catch node errors.

```json
{
  "id": "unique-id",
  "type": "catch",
  "z": "tab-id",
  "name": "Error Handler",
  "scope": ["node-id-1", "node-id-2"],  // Specific nodes or null for all
  "uncaught": false,    // Catch uncaught errors
  "x": 100,
  "y": 200,
  "wires": [[]]
}
```

### status
Monitor node status.

```json
{
  "id": "unique-id",
  "type": "status",
  "z": "tab-id",
  "name": "Status Monitor",
  "scope": ["node-id"],  // Specific nodes or null for all
  "x": 100,
  "y": 300,
  "wires": [[]]
}
```

## Configuration Nodes

### mqtt-broker
MQTT broker configuration (referenced by MQTT nodes).

```json
{
  "id": "broker-config-id",
  "type": "mqtt-broker",
  "name": "MQTT Broker",
  "broker": "localhost",
  "port": "1883",
  "clientid": "",
  "autoConnect": true,
  "usetls": false,
  "protocolVersion": "4",  // 3|4|5
  "keepalive": "60",
  "cleansession": true,
  "birthTopic": "",
  "birthQos": "0",
  "birthPayload": "",
  "birthMsg": {},
  "closeTopic": "",
  "closeQos": "0",
  "closePayload": "",
  "closeMsg": {},
  "willTopic": "",
  "willQos": "0",
  "willPayload": "",
  "willMsg": {},
  "sessionExpiry": ""
}
```

## Custom Properties

### Environment Variables
Use `$(ENV_VAR)` syntax in string properties.

### JSONata Expressions
Use JSONata for dynamic property values:
- Set property type to "jsonata"
- Use expressions like `$sum(payload)` or `payload.temperature * 1.8 + 32`

### Message Properties
Common message properties:
- `msg.payload`: Primary data
- `msg.topic`: Message topic/category
- `msg._msgid`: Unique message ID
- `msg.parts`: Split/join metadata
- `msg.req`/`msg.res`: HTTP request/response objects
- `msg.error`: Error information (in catch nodes)