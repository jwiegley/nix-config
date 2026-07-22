/**
 * Async Function Node Template
 *
 * This template demonstrates async operations in Node-RED function nodes.
 * Use this when you need to perform asynchronous operations like API calls,
 * database queries, or delayed processing.
 */

// Example 1: Simple async with setTimeout
async function delayedProcessing() {
    // Simulate async operation
    await new Promise(resolve => setTimeout(resolve, 1000));

    msg.payload = {
        ...msg.payload,
        processed: true,
        timestamp: Date.now()
    };

    node.send(msg);
    node.done();
}

// Example 2: Multiple async operations with error handling
async function complexAsyncOperation() {
    try {
        // Run multiple async operations in parallel
        const results = await Promise.all([
            fetchData(msg.payload.url1),
            fetchData(msg.payload.url2),
            processData(msg.payload.data)
        ]);

        msg.payload = {
            results: results,
            success: true
        };

        node.send([msg, null]); // Success output

    } catch (error) {
        node.error(`Async operation failed: ${error.message}`, msg);

        msg.payload = {
            error: error.message,
            originalPayload: msg.payload
        };

        node.send([null, msg]); // Error output
    }

    node.done();
}

// Example 3: Sequential async operations
async function sequentialProcessing() {
    try {
        // Step 1: Validate
        const isValid = await validateInput(msg.payload);
        if (!isValid) {
            throw new Error('Validation failed');
        }

        // Step 2: Process
        const processed = await processInput(msg.payload);

        // Step 3: Store
        await storeResult(processed);

        msg.payload = processed;
        node.send(msg);

    } catch (error) {
        node.error(error.message, msg);
    }

    node.done();
}

// Helper functions (replace with actual implementations)
async function fetchData(url) {
    // Simulate API call
    return new Promise((resolve) => {
        setTimeout(() => resolve({ data: 'sample' }), 500);
    });
}

async function processData(data) {
    // Simulate data processing
    return new Promise((resolve) => {
        setTimeout(() => resolve(data), 300);
    });
}

async function validateInput(input) {
    // Simulate validation
    return input !== null && input !== undefined;
}

async function processInput(input) {
    // Simulate processing
    return { ...input, processed: true };
}

async function storeResult(result) {
    // Simulate storage operation
    context.set('lastResult', result);
}

// Main execution - choose your pattern
// Uncomment the pattern you want to use

// delayedProcessing();
// complexAsyncOperation();
sequentialProcessing();

// IMPORTANT: Return null to prevent immediate message passing
// The async function will handle sending messages via node.send()
return null;