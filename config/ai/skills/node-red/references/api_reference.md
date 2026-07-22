# Node-RED Admin API Reference

## Authentication

If `httpAdminAuth` is configured in settings.js, include authentication headers:

```bash
# Basic Auth
curl -u admin:password http://localhost:1880/flows

# Bearer Token
curl -H "Authorization: Bearer <access_token>" http://localhost:1880/flows
```

## Flow Management

The Flows API has two versions. **v1 (the default)** works with a bare JSON
array of nodes — this is what the recipes in SKILL.md use. **v2** wraps the
array in an envelope with a revision id for optimistic locking, and only
applies when the request carries the header `Node-RED-API-Version: v2`.

### GET /flows
Retrieve the active flow configuration.

**Response (v1, default):** a JSON array of all nodes, including tab and
subflow definitions:
```json
[
  { "id": "tab-id", "type": "tab", "label": "Flow 1" },
  { "id": "node-id", "type": "inject", "z": "tab-id", "wires": [[]] }
]
```

**Response (v2, requires `Node-RED-API-Version: v2` header):**
```json
{
  "flows": [...],      // Array of flow nodes
  "rev": "abc123"      // Revision ID for update operations
}
```

### POST /flows
Deploy complete flow configuration.

**Request (v1, default):** the body is the complete flow array itself:
```json
[...]
```

**Request (v2, requires `Node-RED-API-Version: v2` header):**
```json
{
  "flows": [...],      // Complete flow array
  "rev": "abc123"      // Optional: revision for conflict detection
}
```
With v2, a stale `rev` is rejected with a `conflict` error unless the
deployment type is `reload`.

**Headers:**
- `Node-RED-Deployment-Type`: full|nodes|flows|reload
- `Node-RED-API-Version`: v2 (only when using the v2 envelope)

### POST /flow
Add a new flow/tab.

**Request:**
```json
{
  "id": "optional-id",
  "label": "Flow Name",
  "nodes": [...],       // Nodes in this flow
  "configs": [...]      // Config nodes used by this flow
}
```

### GET /flow/:id
Get a specific flow configuration.

**Response:**
```json
{
  "id": "flow-id",
  "label": "Flow Name",
  "nodes": [...],
  "configs": [...]
}
```

### PUT /flow/:id
Update a specific flow.

**Request:**
```json
{
  "id": "flow-id",
  "label": "Updated Name",
  "nodes": [...],
  "configs": [...]
}
```

### DELETE /flow/:id
Delete a flow.

**Response:**
```json
{
  "removed": ["node-id-1", "node-id-2"]
}
```

## Node Management

### POST /nodes
Install a new node module.

**Request:**
```json
{
  "module": "node-red-contrib-example",
  "version": "1.0.0"    // Optional
}
```

### GET /nodes
List all installed nodes.

**Response:**
```json
[
  {
    "id": "node-red/inject",
    "name": "inject",
    "types": ["inject"],
    "enabled": true,
    "module": "node-red",
    "version": "3.0.0"
  }
]
```

### GET /nodes/:module
Get specific node module info.

### DELETE /nodes/:module
Uninstall a node module.

### PUT /nodes/:module
Enable/disable a node module.

**Request:**
```json
{
  "enabled": true
}
```

## Context Store

### GET /context/:scope
Get context data.

**Scopes:**
- `global`: Global context
- `flow/:flowId`: Flow context
- `node/:nodeId`: Node context

**Query Parameters:**
- `store`: Context store name (default: "default")

### GET /context/:scope/:key
Get specific context value.

### DELETE /context/:scope/:key
Delete context value.

## Settings

### GET /settings
Get runtime settings (publicly accessible).

**Response:**
```json
{
  "httpNodeRoot": "/",
  "version": "3.0.0",
  "context": {
    "default": "memory",
    "stores": ["memory", "file"]
  },
  "flowEncryptionType": "system",
  "user": {
    "username": "admin"
  }
}
```

## Authentication Endpoints

### POST /auth/token
Get access token.

**Request:**
```json
{
  "client_id": "node-red-editor",
  "grant_type": "password",
  "username": "admin",
  "password": "password",
  "scope": "read write"
}
```

**Response:**
```json
{
  "access_token": "token-string",
  "expires_in": 604800,
  "token_type": "Bearer"
}
```

### POST /auth/revoke
Revoke access token.

**Request:**
```json
{
  "token": "access-token"
}
```

## Library

### GET /library/flows
List saved flows in library.

### GET /library/flows/:path
Get specific library flow.

### POST /library/flows/:path
Save flow to library.

**Request:**
```json
{
  "flows": [...],
  "description": "Flow description"
}
```

## Debug

### GET /debug/view
Get debug messages (WebSocket endpoint also available).

### POST /debug/:nodeId/:state
Enable/disable debug node.

**State:** enable|disable

## UI Editor

### GET /red/*
Serve the Node-RED editor UI.

### GET /
Redirect to editor (if httpAdminRoot is set).

## Projects API (if enabled)

### GET /projects
List all projects.

### POST /projects
Create new project.

**Request:**
```json
{
  "name": "my-project",
  "summary": "Project description",
  "files": {
    "flow": "flows.json",
    "credentials": "flows_cred.json"
  },
  "git": {
    "remotes": {
      "origin": {
        "url": "https://github.com/user/repo.git"
      }
    }
  }
}
```

### GET /projects/:name
Get project details.

### PUT /projects/:name
Update project.

### DELETE /projects/:name
Delete project.

### PUT /projects/:name/stage
Stage files for commit.

**Request:**
```json
{
  "files": ["flows.json", "package.json"]
}
```

### POST /projects/:name/commit
Commit staged changes.

**Request:**
```json
{
  "message": "Commit message"
}
```

## Execution Control

### POST /inject/:nodeId
Trigger inject node programmatically.

**Response:**
```json
{
  "status": "ok"
}
```

## Health Check

### GET /diagnostics
Get system diagnostics (if enabled).

**Response:**
```json
{
  "version": "3.0.0",
  "nodejs": "18.0.0",
  "os": {
    "platform": "linux",
    "release": "5.10.0"
  },
  "runtime": {
    "modules": [...],
    "settings": {...}
  }
}
```

## Error Responses

### Error Format
```json
{
  "code": "error_code",
  "message": "Human readable message",
  "details": {}
}
```

### Common Error Codes
- `invalid_api_version`: API version mismatch
- `invalid_flow`: Flow validation failed
- `module_not_found`: Node module not found
- `not_found`: Resource not found
- `permission_denied`: Insufficient permissions
- `conflict`: Revision conflict
- `unexpected_error`: Internal server error

## WebSocket Endpoints

### /comms
Real-time communication for editor.

**Events:**
- `status`: Node status updates
- `debug`: Debug messages
- `notification`: System notifications

## CORS Configuration

Configure in settings.js:
```javascript
httpNodeCors: {
  origin: "*",
  methods: "GET,PUT,POST,DELETE"
}
```

## Example Usage

### Deploy Flow via cURL
```bash
# Get current flows (v1: the body is a bare JSON array)
TOKEN=$(cat /run/secrets/node-red-admin-token)
FLOWS=$(curl -s -H "Authorization: Bearer $TOKEN" http://localhost:1880/flows)

# Modify and deploy (the body is the array itself)
curl -X POST http://localhost:1880/flows \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Node-RED-Deployment-Type: full" \
  -d "$FLOWS"
```

### Python Example
```python
import requests

with open('/run/secrets/node-red-admin-token') as f:
    token = f.read().strip()
headers = {'Authorization': f'Bearer {token}'}

# Get flows (v1: the response body is the flow array itself)
resp = requests.get('http://localhost:1880/flows', headers=headers)
flows = resp.json()  # a list of node objects

# Add a new node
flows.append({
    "id": "a1b2c3d4e5f60718",  # 16 hex chars (scripts/generate_uuid.py)
    "type": "debug",
    "z": "flow-tab-id",
    "name": "New Debug",
    "x": 300,
    "y": 200,
    "wires": []
})

# Deploy
requests.post(
    'http://localhost:1880/flows',
    json=flows,
    headers={**headers, 'Node-RED-Deployment-Type': 'nodes'}
)
```