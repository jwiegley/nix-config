/**
 * Context Storage Function Node Template
 *
 * This template demonstrates how to use context storage in Node-RED.
 * Context allows you to store data between message passes.
 *
 * Three levels of context:
 * - node.context() - Local to this node only
 * - flow.context() - Shared across all nodes in this flow/tab
 * - global.context() - Shared across all flows
 */

// ========================================
// NODE CONTEXT (Local Storage)
// ========================================

// Simple counter example
let nodeCounter = context.get('counter') || 0;
nodeCounter++;
context.set('counter', nodeCounter);

// Store complex data structures
let nodeData = context.get('nodeData') || {
    messages: [],
    lastUpdate: null,
    statistics: {
        total: 0,
        errors: 0,
        success: 0
    }
};

// Update node data
nodeData.messages.push(msg.payload);
nodeData.lastUpdate = Date.now();
nodeData.statistics.total++;

// Keep only last 10 messages
if (nodeData.messages.length > 10) {
    nodeData.messages.shift();
}

context.set('nodeData', nodeData);

// ========================================
// FLOW CONTEXT (Flow-wide Storage)
// ========================================

// Share data across nodes in the same flow
let flowState = flow.get('sharedState') || {
    status: 'idle',
    activeRequests: 0,
    configuration: {}
};

// Update flow state
flowState.activeRequests++;
flowState.status = 'processing';
flow.set('sharedState', flowState);

// Use flow context for caching
let cache = flow.get('cache') || {};
const cacheKey = msg.topic || 'default';

if (!cache[cacheKey] || Date.now() - cache[cacheKey].timestamp > 60000) {
    // Cache miss or expired (60 seconds)
    cache[cacheKey] = {
        data: msg.payload,
        timestamp: Date.now()
    };
    flow.set('cache', cache);
}

// ========================================
// GLOBAL CONTEXT (System-wide Storage)
// ========================================

// Access global configuration
let globalConfig = global.get('systemConfig') || {
    apiEndpoint: 'https://api.example.com',
    apiKey: 'demo-key',
    retryAttempts: 3,
    timeout: 5000
};

// Store global metrics
let metrics = global.get('systemMetrics') || {
    startTime: Date.now(),
    totalMessages: 0,
    errorCount: 0,
    throughput: []
};

metrics.totalMessages++;
global.set('systemMetrics', metrics);

// ========================================
// PERSISTENT STORAGE (File-based)
// ========================================

// If configured in settings.js, you can use persistent storage
// This survives Node-RED restarts

// Store to persistent file storage
context.set('persistentData', msg.payload, 'file');

// Retrieve from persistent storage
let persistentValue = context.get('persistentData', 'file') || null;

// ========================================
// CONTEXT MANAGEMENT PATTERNS
// ========================================

// Pattern 1: Atomic updates with callbacks
context.get('atomicCounter', (err, value) => {
    if (err) {
        node.error('Failed to get context', msg);
        return;
    }

    const newValue = (value || 0) + 1;

    context.set('atomicCounter', newValue, (err) => {
        if (err) {
            node.error('Failed to set context', msg);
        }
    });
});

// Pattern 2: TTL (Time To Live) implementation
function setWithTTL(key, value, ttlSeconds) {
    const data = {
        value: value,
        expiry: Date.now() + (ttlSeconds * 1000)
    };
    context.set(key, data);
}

function getWithTTL(key) {
    const data = context.get(key);

    if (!data) return null;

    if (Date.now() > data.expiry) {
        // Expired, clean up
        context.set(key, null);
        return null;
    }

    return data.value;
}

// Use TTL pattern
setWithTTL('tempData', msg.payload, 300); // 5 minutes TTL
const tempValue = getWithTTL('tempData');

// Pattern 3: Circular buffer for time-series data
let timeSeries = context.get('timeSeries') || {
    maxSize: 100,
    data: []
};

timeSeries.data.push({
    timestamp: Date.now(),
    value: msg.payload
});

// Maintain maximum size
while (timeSeries.data.length > timeSeries.maxSize) {
    timeSeries.data.shift();
}

context.set('timeSeries', timeSeries);

// Calculate statistics on time-series
const recentData = timeSeries.data.slice(-10); // Last 10 values
const average = recentData.reduce((sum, item) => sum + item.value, 0) / recentData.length;

// ========================================
// CLEANUP PATTERN
// ========================================

// Clean up old context data periodically
const lastCleanup = context.get('lastCleanup') || 0;
const cleanupInterval = 3600000; // 1 hour

if (Date.now() - lastCleanup > cleanupInterval) {
    // Perform cleanup
    const allKeys = context.keys();

    allKeys.forEach(key => {
        if (key.startsWith('temp_')) {
            // Remove temporary keys
            context.set(key, undefined);
        }
    });

    context.set('lastCleanup', Date.now());
}

// ========================================
// OUTPUT MESSAGE
// ========================================

// Prepare output with context information
msg.payload = {
    original: msg.payload,
    nodeContext: {
        counter: nodeCounter,
        messagesStored: nodeData.messages.length
    },
    flowContext: {
        sharedStatus: flowState.status,
        cacheSize: Object.keys(cache).length
    },
    globalContext: {
        totalMessages: metrics.totalMessages,
        config: globalConfig.apiEndpoint
    },
    statistics: {
        average: average || 0,
        timeSeriesCount: timeSeries.data.length
    }
};

// Add status to node
const status = nodeCounter % 2 === 0 ? 'even' : 'odd';
node.status({
    fill: status === 'even' ? 'green' : 'yellow',
    shape: 'dot',
    text: `Count: ${nodeCounter} (${status})`
});

return msg;