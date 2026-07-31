# Node-RED Function Node Code Snippets

## Message Manipulation

### Clone message for multiple outputs
```javascript
// Send different data to multiple outputs
let msg1 = RED.util.cloneMessage(msg);
let msg2 = RED.util.cloneMessage(msg);

msg1.payload = "Output 1";
msg2.payload = "Output 2";

return [msg1, msg2];
```

### Conditional routing
```javascript
// Route to different outputs based on value
if (msg.payload > 100) {
    return [msg, null, null];  // Output 1
} else if (msg.payload > 50) {
    return [null, msg, null];  // Output 2
} else {
    return [null, null, msg];  // Output 3
}
```

### Message aggregation
```javascript
// Collect multiple messages before processing
let messages = context.get('messages') || [];
messages.push(msg.payload);

if (messages.length >= 5) {
    msg.payload = messages;
    context.set('messages', []);
    return msg;
} else {
    context.set('messages', messages);
    return null;  // Don't send anything yet
}
```

## Asynchronous Operations

### Basic async with setTimeout
```javascript
// Delay message by 1 second
setTimeout(function() {
    msg.payload = "Delayed response";
    node.send(msg);
    node.done();
}, 1000);
return null;  // Don't return anything immediately
```

### HTTP request with async/await

`require()` is not available inside function nodes. To use a Node.js module,
add it on the function node's **Setup** tab (stored in the node's `libs`;
enabled by default via `functionExternalModules` in settings.js). The example
below assumes the `https` module was added on the Setup tab with variable
name `https`. For simple cases, prefer wiring an `http request` node instead
of issuing requests from function code.

```javascript
// Make async HTTP request ("https" added on the Setup tab)
async function fetchData() {
    try {
        const response = await new Promise((resolve, reject) => {
            https.get('https://api.example.com/data', (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => resolve(JSON.parse(data)));
            }).on('error', reject);
        });

        msg.payload = response;
        node.send(msg);
    } catch (error) {
        node.error("Failed to fetch data: " + error, msg);
    }
    node.done();
}

fetchData();
return null;
```

### Multiple async operations
```javascript
// Process multiple async operations
async function processMultiple() {
    const promises = msg.payload.map(async (item) => {
        // Simulate async operation
        await new Promise(resolve => setTimeout(resolve, 100));
        return item * 2;
    });

    try {
        const results = await Promise.all(promises);
        msg.payload = results;
        node.send(msg);
    } catch (error) {
        node.error("Processing failed: " + error, msg);
    }
    node.done();
}

processMultiple();
return null;
```

## Context Storage

### Counter with persistence
```javascript
// Increment counter stored in context
let count = context.get('count') || 0;
count++;
context.set('count', count);

msg.payload = {
    count: count,
    timestamp: new Date().toISOString()
};
return msg;
```

### Flow-wide shared data
```javascript
// Share data across nodes in the same flow
let flowData = flow.get('sharedData') || {};
flowData[msg.topic] = msg.payload;
flow.set('sharedData', flowData);

// Get all collected data
msg.payload = flow.get('sharedData');
return msg;
```

### Global configuration
```javascript
// Access global configuration
const config = global.get('appConfig') || {
    apiUrl: 'https://api.example.com',
    timeout: 5000,
    retries: 3
};

msg.url = config.apiUrl + '/endpoint';
msg.timeout = config.timeout;
return msg;
```

### Persistent storage with file store
```javascript
// Store to specific context store (configured in settings.js)
context.set('persistentData', msg.payload, 'file');

// Retrieve from file store
let data = context.get('persistentData', 'file') || {};
msg.payload = data;
return msg;
```

## Error Handling

### Try-catch with error node trigger
```javascript
try {
    // Risky operation
    let data = JSON.parse(msg.payload);
    msg.payload = data.value * 2;
    return msg;
} catch (error) {
    // Trigger catch node
    node.error("Parse error: " + error.message, msg);
    return null;
}
```

### Validation with detailed errors
```javascript
// Validate input with detailed error messages
const errors = [];

if (!msg.payload) {
    errors.push("Payload is required");
}

if (typeof msg.payload !== 'object') {
    errors.push("Payload must be an object");
}

if (!msg.payload.id) {
    errors.push("ID field is required");
}

if (errors.length > 0) {
    msg.payload = {
        error: true,
        messages: errors,
        original: msg.payload
    };
    node.error("Validation failed", msg);
    return [null, msg];  // Send to error output
} else {
    return [msg, null];  // Send to success output
}
```

### Retry logic
```javascript
// Retry failed operations
let retries = context.get('retries') || 0;
const maxRetries = 3;

function attemptOperation() {
    try {
        // Simulate operation that might fail
        if (Math.random() > 0.5) {
            throw new Error("Random failure");
        }

        // Success
        msg.payload = "Operation successful";
        context.set('retries', 0);
        return msg;

    } catch (error) {
        retries++;
        context.set('retries', retries);

        if (retries < maxRetries) {
            node.warn(`Attempt ${retries} failed, retrying...`);
            setTimeout(() => {
                node.send(attemptOperation());
                node.done();
            }, 1000 * retries);  // Linear backoff: 1s, 2s, 3s
            return null;
        } else {
            node.error(`Failed after ${maxRetries} attempts`, msg);
            context.set('retries', 0);
            return null;
        }
    }
}

return attemptOperation();
```

## Data Transformation

### Array processing
```javascript
// Process array with map, filter, reduce
if (Array.isArray(msg.payload)) {
    msg.payload = msg.payload
        .filter(item => item.active)
        .map(item => ({
            id: item.id,
            name: item.name.toUpperCase(),
            value: item.value * 1.1
        }))
        .reduce((acc, item) => {
            acc[item.id] = item;
            return acc;
        }, {});
}
return msg;
```

### CSV to JSON
```javascript
// Convert CSV string to JSON
const lines = msg.payload.split('\n');
const headers = lines[0].split(',').map(h => h.trim());
const data = [];

for (let i = 1; i < lines.length; i++) {
    if (lines[i].trim() === '') continue;

    const values = lines[i].split(',');
    const obj = {};

    headers.forEach((header, index) => {
        obj[header] = values[index]?.trim() || '';
    });

    data.push(obj);
}

msg.payload = data;
return msg;
```

### JSON flattening
```javascript
// Flatten nested object
function flatten(obj, prefix = '') {
    let result = {};

    for (let key in obj) {
        if (obj.hasOwnProperty(key)) {
            const newKey = prefix ? `${prefix}.${key}` : key;

            if (typeof obj[key] === 'object' && obj[key] !== null && !Array.isArray(obj[key])) {
                Object.assign(result, flatten(obj[key], newKey));
            } else {
                result[newKey] = obj[key];
            }
        }
    }

    return result;
}

msg.payload = flatten(msg.payload);
return msg;
```

## Time-based Operations

### Rate limiting
```javascript
// Limit messages to 1 per second
const lastTime = context.get('lastTime') || 0;
const now = Date.now();

if (now - lastTime < 1000) {
    return null;  // Drop message
}

context.set('lastTime', now);
return msg;
```

### Time window aggregation
```javascript
// Collect messages for 5 seconds then send batch
let buffer = context.get('buffer') || [];
let windowStart = context.get('windowStart') || Date.now();

buffer.push(msg.payload);

if (Date.now() - windowStart > 5000) {
    msg.payload = {
        count: buffer.length,
        data: buffer,
        window: {
            start: new Date(windowStart).toISOString(),
            end: new Date().toISOString()
        }
    };

    context.set('buffer', []);
    context.set('windowStart', Date.now());

    return msg;
} else {
    context.set('buffer', buffer);
    return null;
}
```

### Scheduled operations
```javascript
// Run operation at specific time
const now = new Date();
const scheduledHour = 14;  // 2 PM

if (now.getHours() === scheduledHour && !context.get('ranToday')) {
    context.set('ranToday', true);

    // Reset flag at midnight
    const tomorrow = new Date(now);
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(0, 0, 0, 0);

    setTimeout(() => {
        context.set('ranToday', false);
    }, tomorrow - now);

    msg.payload = "Scheduled operation executed";
    return msg;
}

return null;
```

## Advanced Patterns

### State machine
```javascript
// Simple state machine implementation
const states = {
    IDLE: 'idle',
    PROCESSING: 'processing',
    ERROR: 'error',
    COMPLETE: 'complete'
};

let currentState = context.get('state') || states.IDLE;
const event = msg.topic;

switch (currentState) {
    case states.IDLE:
        if (event === 'start') {
            currentState = states.PROCESSING;
            msg.payload = "Started processing";
        }
        break;

    case states.PROCESSING:
        if (event === 'complete') {
            currentState = states.COMPLETE;
            msg.payload = "Processing complete";
        } else if (event === 'error') {
            currentState = states.ERROR;
            msg.payload = "Error occurred";
        }
        break;

    case states.ERROR:
        if (event === 'reset') {
            currentState = states.IDLE;
            msg.payload = "Reset to idle";
        }
        break;

    case states.COMPLETE:
        if (event === 'reset') {
            currentState = states.IDLE;
            msg.payload = "Reset to idle";
        }
        break;
}

context.set('state', currentState);
msg.state = currentState;
return msg;
```

### Message queue with priority
```javascript
// Priority queue implementation
let queue = context.get('queue') || [];

// Add message to queue with priority
if (msg.topic === 'enqueue') {
    queue.push({
        priority: msg.priority || 5,
        payload: msg.payload,
        timestamp: Date.now()
    });

    // Sort by priority (lower number = higher priority)
    queue.sort((a, b) => a.priority - b.priority);
    context.set('queue', queue);

    msg.payload = `Queued. Position: ${queue.length}`;
    return msg;
}

// Dequeue highest priority message
if (msg.topic === 'dequeue') {
    if (queue.length > 0) {
        const item = queue.shift();
        context.set('queue', queue);

        msg.payload = item.payload;
        msg.priority = item.priority;
        msg.queueTime = Date.now() - item.timestamp;
        return msg;
    } else {
        msg.payload = "Queue empty";
        return msg;
    }
}

return null;
```

### Circuit breaker pattern
```javascript
// Prevent cascading failures
const CLOSED = 'closed';
const OPEN = 'open';
const HALF_OPEN = 'half_open';

let state = context.get('circuitState') || CLOSED;
let failures = context.get('failures') || 0;
let lastFailTime = context.get('lastFailTime') || 0;

const maxFailures = 3;
const timeout = 60000;  // 1 minute

// Check if circuit should reset
if (state === OPEN && Date.now() - lastFailTime > timeout) {
    state = HALF_OPEN;
    node.status({fill:"yellow", shape:"ring", text:"half-open"});
}

if (state === OPEN) {
    msg.payload = {
        error: "Circuit breaker is open",
        retryAfter: timeout - (Date.now() - lastFailTime)
    };
    return [null, msg];  // Error output
}

// Simulate operation
try {
    // Your operation here
    if (Math.random() > 0.7) {
        throw new Error("Operation failed");
    }

    // Success
    if (state === HALF_OPEN) {
        state = CLOSED;
        failures = 0;
        node.status({fill:"green", shape:"dot", text:"closed"});
    }

    context.set('circuitState', state);
    context.set('failures', failures);

    return [msg, null];  // Success output

} catch (error) {
    failures++;

    if (failures >= maxFailures) {
        state = OPEN;
        lastFailTime = Date.now();
        node.status({fill:"red", shape:"ring", text:"open"});
    }

    context.set('circuitState', state);
    context.set('failures', failures);
    context.set('lastFailTime', lastFailTime);

    msg.payload = {
        error: error.message,
        failures: failures,
        state: state
    };

    return [null, msg];  // Error output
}
```

## Logging and Debugging

### Structured logging
```javascript
// Create structured log entries
function log(level, message, data = {}) {
    const logEntry = {
        timestamp: new Date().toISOString(),
        level: level,
        message: message,
        nodeId: node.id,
        nodeName: node.name || 'unnamed',
        data: data
    };

    switch(level) {
        case 'error':
            node.error(JSON.stringify(logEntry));
            break;
        case 'warn':
            node.warn(JSON.stringify(logEntry));
            break;
        default:
            node.log(JSON.stringify(logEntry));
    }
}

// Usage
log('info', 'Processing started', {count: msg.payload.length});

try {
    // Your operation here
} catch (err) {
    log('error', 'Processing failed', {error: err.message});
}

return msg;
```

### Performance monitoring
```javascript
// Measure execution time
const startTime = Date.now();

// Your operation here
// ...

const executionTime = Date.now() - startTime;

msg.performance = {
    executionTime: executionTime,
    timestamp: new Date().toISOString()
};

if (executionTime > 1000) {
    node.warn(`Slow execution: ${executionTime}ms`);
}

return msg;
```