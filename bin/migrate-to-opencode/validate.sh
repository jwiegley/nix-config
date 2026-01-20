#!/usr/bin/env bash
#
# Validate OpenCode configuration after migration
#
# This script checks that the migrated configuration is valid and complete.
#
set -euo pipefail

OPENCODE_CONFIG="${OPENCODE_CONFIG:-$HOME/.config/opencode}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

log_check() {
    echo -e "${BLUE}[CHECK]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}  ✓${NC} $*"
}

log_fail() {
    echo -e "${RED}  ✗${NC} $*"
    ((ERRORS++)) || true
}

log_warn() {
    echo -e "${YELLOW}  ⚠${NC} $*"
    ((WARNINGS++)) || true
}

# =============================================================================
# Validation Functions
# =============================================================================

check_directory_structure() {
    log_check "Checking directory structure..."

    local dirs=(
        "$OPENCODE_CONFIG"
        "$OPENCODE_CONFIG/command"
        "$OPENCODE_CONFIG/agent"
    )

    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_pass "$dir exists"
        else
            log_fail "$dir missing"
        fi
    done

    # Optional directories
    local optional_dirs=(
        "$OPENCODE_CONFIG/plugin"
        "$OPENCODE_CONFIG/knowledge"
        "$OPENCODE_CONFIG/tool"
    )

    for dir in "${optional_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_pass "$dir exists (optional)"
        fi
    done
}

check_opencode_json() {
    log_check "Checking opencode.json..."

    local config="$OPENCODE_CONFIG/opencode.json"

    if [[ ! -f "$config" ]]; then
        log_fail "opencode.json not found"
        return
    fi

    # Check JSON validity
    if jq empty "$config" 2>/dev/null; then
        log_pass "Valid JSON syntax"
    else
        log_fail "Invalid JSON syntax"
        return
    fi

    # Check schema reference
    if jq -e '."$schema"' "$config" >/dev/null 2>&1; then
        log_pass "Schema reference present"
    else
        log_warn "No schema reference (recommended: https://opencode.ai/config.json)"
    fi

    # Check model
    local model
    model=$(jq -r '.model // empty' "$config")
    if [[ -n "$model" ]]; then
        log_pass "Model configured: $model"
    else
        log_warn "No default model configured"
    fi

    # Check MCP servers
    local mcp_count
    mcp_count=$(jq '.mcp | keys | length' "$config" 2>/dev/null || echo "0")
    if [[ "$mcp_count" -gt 0 ]]; then
        log_pass "$mcp_count MCP server(s) configured"
    else
        log_warn "No MCP servers configured"
    fi
}

check_commands() {
    log_check "Checking commands..."

    local cmd_dir="$OPENCODE_CONFIG/command"

    if [[ ! -d "$cmd_dir" ]]; then
        log_warn "Commands directory not found"
        return
    fi

    local count=0
    local valid=0
    local invalid=0

    for cmd in "$cmd_dir"/*.md; do
        if [[ ! -f "$cmd" ]]; then
            continue
        fi

        ((count++)) || true
        local filename
        filename=$(basename "$cmd")

        # Check for frontmatter
        if head -1 "$cmd" | grep -q "^---"; then
            # Check for description
            if grep -q "^description:" "$cmd"; then
                ((valid++)) || true
            else
                log_warn "$filename: No description in frontmatter"
                ((invalid++)) || true
            fi
        else
            log_warn "$filename: No YAML frontmatter"
            ((invalid++)) || true
        fi
    done

    if [[ $count -gt 0 ]]; then
        log_pass "Found $count commands ($valid valid, $invalid with issues)"
    else
        log_warn "No commands found"
    fi
}

check_agents() {
    log_check "Checking agents..."

    local agent_dir="$OPENCODE_CONFIG/agent"

    if [[ ! -d "$agent_dir" ]]; then
        log_warn "Agents directory not found"
        return
    fi

    local count=0
    local valid=0
    local invalid=0

    for agent in "$agent_dir"/*.md; do
        if [[ ! -f "$agent" ]]; then
            continue
        fi

        ((count++)) || true
        local filename
        filename=$(basename "$agent")

        # Check for frontmatter
        if head -1 "$agent" | grep -q "^---"; then
            local has_desc has_mode has_model
            has_desc=$(grep -c "^description:" "$agent" || true)
            has_mode=$(grep -c "^mode:" "$agent" || true)
            has_model=$(grep -c "^model:" "$agent" || true)

            if [[ "$has_desc" -gt 0 ]] && [[ "$has_mode" -gt 0 ]]; then
                ((valid++)) || true
            else
                local missing=""
                [[ "$has_desc" -eq 0 ]] && missing+="description "
                [[ "$has_mode" -eq 0 ]] && missing+="mode "
                log_warn "$filename: Missing required fields: $missing"
                ((invalid++)) || true
            fi
        else
            log_warn "$filename: No YAML frontmatter"
            ((invalid++)) || true
        fi
    done

    if [[ $count -gt 0 ]]; then
        log_pass "Found $count agents ($valid valid, $invalid with issues)"
    else
        log_warn "No agents found"
    fi
}

check_plugins() {
    log_check "Checking plugins..."

    local plugin_dir="$OPENCODE_CONFIG/plugin"

    if [[ ! -d "$plugin_dir" ]]; then
        log_pass "No plugins directory (optional)"
        return
    fi

    local count=0
    for plugin in "$plugin_dir"/*.ts; do
        if [[ -f "$plugin" ]]; then
            ((count++)) || true
            local filename
            filename=$(basename "$plugin")

            # Basic syntax check
            if grep -q "export default plugin" "$plugin"; then
                log_pass "$filename: Valid plugin export"
            else
                log_warn "$filename: Missing 'export default plugin'"
            fi
        fi
    done

    if [[ $count -gt 0 ]]; then
        log_pass "Found $count plugin(s)"

        # Check for package.json
        if [[ -f "$OPENCODE_CONFIG/package.json" ]]; then
            log_pass "package.json present"

            # Check if dependencies installed
            if [[ -d "$OPENCODE_CONFIG/node_modules" ]]; then
                log_pass "Dependencies installed"
            else
                log_warn "Dependencies not installed (run: cd $OPENCODE_CONFIG && bun install)"
            fi
        else
            log_warn "package.json missing (required for plugins)"
        fi
    fi
}

check_model_references() {
    log_check "Checking model references..."

    local old_models=("opus" "sonnet" "haiku" "claude-opus" "claude-sonnet" "claude-haiku")
    local issues=0

    # Check agents
    for agent in "$OPENCODE_CONFIG/agent"/*.md 2>/dev/null; do
        if [[ ! -f "$agent" ]]; then
            continue
        fi

        for old_model in "${old_models[@]}"; do
            if grep -q "^model: $old_model$" "$agent"; then
                log_warn "$(basename "$agent"): Uses old model name '$old_model'"
                ((issues++)) || true
            fi
        done
    done

    if [[ $issues -eq 0 ]]; then
        log_pass "All model references use OpenCode format (provider/model)"
    fi
}

# =============================================================================
# Main
# =============================================================================

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "             OpenCode Configuration Validation"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Config directory: $OPENCODE_CONFIG"
echo ""

check_directory_structure
echo ""
check_opencode_json
echo ""
check_commands
echo ""
check_agents
echo ""
check_plugins
echo ""
check_model_references

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "                         Summary"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}All checks passed!${NC}"
    exit 0
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}Passed with $WARNINGS warning(s)${NC}"
    exit 0
else
    echo -e "${RED}Failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    exit 1
fi
