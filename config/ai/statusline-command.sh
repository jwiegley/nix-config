#!/bin/bash

# Read JSON input from stdin
JSON=$(cat)

# Debug: save JSON to file for inspection (optional)
# echo "$JSON" > /tmp/statusline-debug.json 2>/dev/null || true

# Extract project directory and get basename (truncate to 12 chars)
PROJECT_DIR=$(echo "$JSON" | jq -r '.workspace.project_dir // .cwd // "unknown"')
_BASENAME=$(basename "$PROJECT_DIR")
if [ "${#_BASENAME}" -gt 12 ]; then
    SHORT_PROJECT="${_BASENAME:0:12}…"
else
    SHORT_PROJECT="$_BASENAME"
fi

# Check dirty status if in a git repo
DIRTY=""
if git -C "$PROJECT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    if ! git -C "$PROJECT_DIR" diff-index --quiet HEAD -- 2>/dev/null; then
        DIRTY="*"
    fi
fi

# Extract model name
MODEL=$(echo "$JSON" | jq -r '.model.display_name // "Opus"')

# Extract context window info (round to integer to avoid floating-point artifacts)
USED_PCT=$(echo "$JSON" | jq -r '.context_window.used_percentage // 0' | awk '{printf "%.0f", $1}')

# Rate limit allocations
FIVE_HOUR_PCT=$(echo "$JSON" | jq -r '.rate_limits.five_hour.used_percentage // 0' | awk '{printf "%.0f", $1}')
SEVEN_DAY_PCT=$(echo "$JSON" | jq -r '.rate_limits.seven_day.used_percentage // 0' | awk '{printf "%.0f", $1}')

# Generate context bar (11 blocks total) - show used percentage
FILLED=$(awk "BEGIN {printf \"%.0f\", ($USED_PCT / 100) * 11}")
EMPTY=$((11 - FILLED))
CONTEXT_BAR=""
for ((i=0; i<FILLED; i++)); do CONTEXT_BAR="${CONTEXT_BAR}█"; done
for ((i=0; i<EMPTY; i++)); do CONTEXT_BAR="${CONTEXT_BAR}░"; done

CONTEXT_DISPLAY="$CONTEXT_BAR ctx:${USED_PCT}% 5h:${FIVE_HOUR_PCT}% 7d:${SEVEN_DAY_PCT}%"

# Extract token totals
INPUT_TOKENS=$(echo "$JSON" | jq -r '.context_window.total_input_tokens // 0')
OUTPUT_TOKENS=$(echo "$JSON" | jq -r '.context_window.total_output_tokens // 0')

# Format token totals
format_tokens() {
    local tokens=$1
    if [ "$tokens" -ge 1000000 ]; then
        awk "BEGIN {printf \"%.1fM\", $tokens / 1000000}"
    elif [ "$tokens" -ge 1000 ]; then
        awk "BEGIN {printf \"%.0fk\", $tokens / 1000}"
    else
        echo "$tokens"
    fi
}

INPUT_FMT=$(format_tokens $INPUT_TOKENS)
OUTPUT_FMT=$(format_tokens $OUTPUT_TOKENS)

TOKENS_DISPLAY="↓$INPUT_FMT ↑$OUTPUT_FMT"

# Lines changed
LINES_ADDED=$(echo "$JSON" | jq -r '.cost.total_lines_added // 0')
LINES_REMOVED=$(echo "$JSON" | jq -r '.cost.total_lines_removed // 0')
LINES_DISPLAY="+$LINES_ADDED/-$LINES_REMOVED"

# Calculate cache hit rate from current usage
CACHE_READ=$(echo "$JSON" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
TOTAL_INPUT=$(echo "$JSON" | jq -r '.context_window.current_usage.input_tokens // 1')
CACHE_CREATION=$(echo "$JSON" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
TOTAL_CACHE_INPUT=$((CACHE_READ + TOTAL_INPUT + CACHE_CREATION))

CACHE_HIT_RATE=0
if [ "$TOTAL_CACHE_INPUT" -gt 0 ]; then
    CACHE_HIT_RATE=$(awk "BEGIN {printf \"%.0f\", ($CACHE_READ / $TOTAL_CACHE_INPUT) * 100}")
fi

CACHE_DISPLAY="cache:${CACHE_HIT_RATE}%"

# Calculate throughput (output tokens / API time in seconds)
API_TIME_MS=$(echo "$JSON" | jq -r '.cost.total_api_duration_ms // 0')
API_TIME_SEC=$(awk "BEGIN {printf \"%.0f\", $API_TIME_MS / 1000}")

THROUGHPUT=0
if [ "$API_TIME_SEC" -gt 0 ] && [ "$OUTPUT_TOKENS" -gt 0 ]; then
    THROUGHPUT=$(awk "BEGIN {printf \"%.1f\", $OUTPUT_TOKENS / $API_TIME_SEC}")
fi

THROUGHPUT_DISPLAY="${THROUGHPUT} tok/s"

# Format API time
format_time() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [ "$hours" -gt 0 ]; then
        printf "%dh%02dm" $hours $minutes
    elif [ "$minutes" -gt 0 ]; then
        printf "%dm%02ds" $minutes $secs
    else
        printf "%ds" $secs
    fi
}

API_TIME_DISPLAY=$(format_time $API_TIME_SEC)

# Extract cost
COST=$(echo "$JSON" | jq -r '.cost.total_cost_usd // 0')
COST_FORMATTED=$(awk "BEGIN {printf \"%.2f\", $COST}")

# Calculate hourly rate
HOURLY_RATE=0
if [ "$API_TIME_SEC" -gt 0 ]; then
    HOURLY_RATE=$(awk "BEGIN {printf \"%.0f\", ($COST / $API_TIME_SEC) * 3600}")
fi

# Output the status line
echo "$SHORT_PROJECT$DIRTY | $MODEL | $CONTEXT_DISPLAY | $TOKENS_DISPLAY | $LINES_DISPLAY | $CACHE_DISPLAY | $API_TIME_DISPLAY"
