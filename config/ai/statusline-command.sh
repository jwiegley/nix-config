#!/bin/bash

set -uo pipefail

# Read JSON input from stdin
JSON=$(cat)

integer_or_zero() {
    awk -v value="${1-}" 'BEGIN {printf "%.0f", value + 0}'
}

# Debug: save JSON to file for inspection (optional)
# echo "$JSON" > /tmp/statusline-debug.json 2>/dev/null || true

# Extract every field in one jq process. NUL delimiters preserve empty values.
FIELDS=()
while IFS= read -r -d '' FIELD; do
    FIELDS+=("$FIELD")
done < <(
    printf '%s' "$JSON" |
        jq -j '[
            .workspace.project_dir // .cwd // "unknown",
            .model.display_name // "Opus",
            .context_window.used_percentage // 0,
            .rate_limits.five_hour.used_percentage // 0,
            .rate_limits.seven_day.used_percentage // 0,
            .context_window.total_input_tokens // 0,
            .context_window.total_output_tokens // 0,
            .cost.total_lines_added // 0,
            .cost.total_lines_removed // 0,
            .context_window.current_usage.cache_read_input_tokens // 0,
            .context_window.current_usage.input_tokens // 1,
            .context_window.current_usage.cache_creation_input_tokens // 0,
            .cost.total_api_duration_ms // 0
        ] | .[] | "\(.)\u0000"'
)

PROJECT_DIR=${FIELDS[0]-unknown}
MODEL=${FIELDS[1]-Opus}
USED_PCT=$(integer_or_zero "${FIELDS[2]-0}")
FIVE_HOUR_PCT=$(integer_or_zero "${FIELDS[3]-0}")
SEVEN_DAY_PCT=$(integer_or_zero "${FIELDS[4]-0}")
INPUT_TOKENS=$(integer_or_zero "${FIELDS[5]-0}")
OUTPUT_TOKENS=$(integer_or_zero "${FIELDS[6]-0}")
LINES_ADDED=$(integer_or_zero "${FIELDS[7]-0}")
LINES_REMOVED=$(integer_or_zero "${FIELDS[8]-0}")
CACHE_READ=$(integer_or_zero "${FIELDS[9]-0}")
TOTAL_INPUT=$(integer_or_zero "${FIELDS[10]-1}")
CACHE_CREATION=$(integer_or_zero "${FIELDS[11]-0}")
API_TIME_MS=$(integer_or_zero "${FIELDS[12]-0}")

# Get the project basename (truncate to 12 chars)
_BASENAME=$(basename "$PROJECT_DIR")
if [ "${#_BASENAME}" -gt 12 ]; then
    SHORT_PROJECT="${_BASENAME:0:12}…"
else
    SHORT_PROJECT="$_BASENAME"
fi

# Check dirty status if in a git repo
DIRTY=""
if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    if ! git -C "$PROJECT_DIR" diff-index --quiet HEAD -- 2>/dev/null; then
        DIRTY="*"
    fi
fi

# Generate context bar (11 blocks total) - show used percentage
FILLED=$(awk -v used_pct="$USED_PCT" 'BEGIN {printf "%.0f", (used_pct / 100) * 11}')
EMPTY=$((11 - FILLED))
CONTEXT_BAR=""
for ((i = 0; i < FILLED; i++)); do CONTEXT_BAR="${CONTEXT_BAR}█"; done
for ((i = 0; i < EMPTY; i++)); do CONTEXT_BAR="${CONTEXT_BAR}░"; done

CONTEXT_DISPLAY="$CONTEXT_BAR ctx:${USED_PCT}% 5h:${FIVE_HOUR_PCT}% 7d:${SEVEN_DAY_PCT}%"

# Format token totals
format_tokens() {
    local tokens=${1-0}
    if [ "$tokens" -ge 1000000 ]; then
        awk -v tokens="$tokens" 'BEGIN {printf "%.1fM", tokens / 1000000}'
    elif [ "$tokens" -ge 1000 ]; then
        awk -v tokens="$tokens" 'BEGIN {printf "%.0fk", tokens / 1000}'
    else
        echo "$tokens"
    fi
}

INPUT_FMT=$(format_tokens "$INPUT_TOKENS")
OUTPUT_FMT=$(format_tokens "$OUTPUT_TOKENS")

TOKENS_DISPLAY="↓$INPUT_FMT ↑$OUTPUT_FMT"

# Lines changed
LINES_DISPLAY="+$LINES_ADDED/-$LINES_REMOVED"

# Calculate cache hit rate from current usage
TOTAL_CACHE_INPUT=$((CACHE_READ + TOTAL_INPUT + CACHE_CREATION))

CACHE_HIT_RATE=0
if [ "$TOTAL_CACHE_INPUT" -gt 0 ]; then
    CACHE_HIT_RATE=$(awk -v cache_read="$CACHE_READ" -v total="$TOTAL_CACHE_INPUT" 'BEGIN {printf "%.0f", (cache_read / total) * 100}')
fi

CACHE_DISPLAY="cache:${CACHE_HIT_RATE}%"

# Convert API time to seconds
API_TIME_SEC=$(awk -v api_time_ms="$API_TIME_MS" 'BEGIN {printf "%.0f", api_time_ms / 1000}')

# Format API time
format_time() {
    local seconds=${1-0}
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [ "$hours" -gt 0 ]; then
        printf "%dh%02dm" "$hours" "$minutes"
    elif [ "$minutes" -gt 0 ]; then
        printf "%dm%02ds" "$minutes" "$secs"
    else
        printf "%ds" "$secs"
    fi
}

API_TIME_DISPLAY=$(format_time "$API_TIME_SEC")

# Output the status line
echo "$SHORT_PROJECT$DIRTY | $MODEL | $CONTEXT_DISPLAY | $TOKENS_DISPLAY | $LINES_DISPLAY | $CACHE_DISPLAY | $API_TIME_DISPLAY"
