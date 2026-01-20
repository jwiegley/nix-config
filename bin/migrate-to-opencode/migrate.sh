#!/usr/bin/env bash
#
# Claude Code to OpenCode Migration Script
#
# This script migrates your Claude Code configuration to OpenCode format.
# It handles commands, agents, skills, settings, and creates necessary plugins.
#
# Usage:
#   ./migrate.sh [--dry-run] [--force] [--verbose]
#
# Options:
#   --dry-run   Show what would be done without making changes
#   --force     Overwrite existing files in destination
#   --verbose   Show detailed output
#
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source directories (Claude Code) - READ ONLY, never modified
CLAUDE_CONFIG="${CLAUDE_CONFIG:-$HOME/.config/claude}"
CLAUDE_COMMANDS="$CLAUDE_CONFIG/commands"
CLAUDE_AGENTS="$CLAUDE_CONFIG/agents"
CLAUDE_SKILLS="$CLAUDE_CONFIG/skills"
CLAUDE_SETTINGS="$CLAUDE_CONFIG/settings.json"

# Destination directories (OpenCode) - write destination
OPENCODE_CONFIG="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
OPENCODE_COMMANDS="$OPENCODE_CONFIG/command"
OPENCODE_AGENTS="$OPENCODE_CONFIG/agent"
OPENCODE_PLUGINS="$OPENCODE_CONFIG/plugin"
OPENCODE_KNOWLEDGE="$OPENCODE_CONFIG/knowledge"
OPENCODE_SETTINGS="$OPENCODE_CONFIG/opencode.json"

# Safety check: ensure source and destination are different
validate_paths() {
    local real_claude real_opencode
    real_claude=$(cd "$CLAUDE_CONFIG" 2>/dev/null && pwd -P || echo "$CLAUDE_CONFIG")
    real_opencode=$(cd "$OPENCODE_CONFIG" 2>/dev/null && pwd -P || echo "$OPENCODE_CONFIG")

    if [[ "$real_claude" == "$real_opencode" ]]; then
        log_error "Source and destination directories are the same! Aborting."
        exit 1
    fi

    # Ensure we never accidentally write to Claude config
    if [[ "$real_opencode" == "$real_claude"* ]]; then
        log_error "Destination is inside source directory! Aborting."
        exit 1
    fi
}

# Options
DRY_RUN=false
FORCE=false
VERBOSE=false

# Counters
COMMANDS_MIGRATED=0
AGENTS_MIGRATED=0
SKILLS_MIGRATED=0
ERRORS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
    ((ERRORS++)) || true
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $*"
    fi
}

log_dry_run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would: $*"
    fi
}

# Check if destination file exists - only create NEW files unless --force
# This ensures we never accidentally overwrite user's existing OpenCode config
check_destination() {
    local dest="$1"
    if [[ -f "$dest" ]] && [[ "$FORCE" != "true" ]]; then
        log_verbose "Skipping $dest (already exists)"
        return 1
    fi
    return 0
}

# Create directory if needed
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "mkdir -p $dir"
        else
            mkdir -p "$dir"
            log_verbose "Created directory: $dir"
        fi
    fi
}

# =============================================================================
# Model Name Mapping
# =============================================================================

# Map Claude Code model names to OpenCode format
map_model_name() {
    local model="$1"
    case "$model" in
        opus|claude-opus|opus-4)
            echo "anthropic/claude-opus-4-5"
            ;;
        sonnet|claude-sonnet|sonnet-4)
            echo "anthropic/claude-sonnet-4-5"
            ;;
        haiku|claude-haiku|haiku-4)
            echo "anthropic/claude-haiku-4-5"
            ;;
        *)
            # If already in provider/model format, keep it
            if [[ "$model" == */* ]]; then
                echo "$model"
            else
                # Default to sonnet for unknown models
                log_warn "Unknown model '$model', defaulting to anthropic/claude-sonnet-4-5"
                echo "anthropic/claude-sonnet-4-5"
            fi
            ;;
    esac
}

# =============================================================================
# Command Migration
# =============================================================================

migrate_command() {
    local src="$1"
    local filename
    filename=$(basename "$src")
    local dest="$OPENCODE_COMMANDS/$filename"

    log_verbose "Processing command: $filename"

    # Skip symbolic links
    if [[ -L "$src" ]]; then
        log_verbose "Skipping symlink: $filename -> $(readlink "$src")"
        return 0
    fi

    if ! check_destination "$dest"; then
        return 0
    fi

    # Read the source file
    local content
    content=$(cat "$src")

    # Check if file already has YAML frontmatter
    if [[ "$content" == ---* ]]; then
        log_verbose "cp \"$src\" \"$dest\""
        # Already has frontmatter, copy as-is but validate
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Copy $filename (has frontmatter)"
        else
            cp "$src" "$dest"
            log_success "Copied command: $filename (preserved frontmatter)"
        fi
    else
        # Need to add frontmatter
        local name="${filename%.md}"
        local description

        # Try to extract a description from the first line or content
        local first_line
        first_line=$(echo "$content" | head -1 | sed 's/^[#* ]*//' | cut -c1-80)

        if [[ -n "$first_line" ]]; then
            description="$first_line"
        else
            description="Migrated from Claude Code"
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Create $filename with frontmatter"
        else
            cat > "$dest" << EOF
---
description: $description
---

$content
EOF
            log_success "Migrated command: $filename (added frontmatter)"
        fi
    fi

    ((COMMANDS_MIGRATED++)) || true
}

migrate_all_commands() {
    log_info "Migrating commands..."
    ensure_dir "$OPENCODE_COMMANDS"

    if [[ ! -d "$CLAUDE_COMMANDS" ]]; then
        log_warn "Claude Code commands directory not found: $CLAUDE_COMMANDS"
        return
    fi

    local count=0
    for cmd in "$CLAUDE_COMMANDS"/*.md; do
        if [[ -f "$cmd" ]]; then
            migrate_command "$cmd"
            ((count++)) || true
        fi
    done

    log_info "Processed $count commands"
}

# =============================================================================
# Agent Migration
# =============================================================================

# Extract a field from YAML frontmatter
extract_yaml_field() {
    local content="$1"
    local field="$2"

    # Extract frontmatter between --- markers
    local frontmatter
    frontmatter=$(echo "$content" | sed -n '/^---$/,/^---$/p' | sed '1d;$d')

    # Extract the field value
    echo "$frontmatter" | grep "^${field}:" | sed "s/^${field}:[[:space:]]*//"
}

# Extract body content (after frontmatter)
extract_body() {
    local content="$1"

    # Remove frontmatter and return the rest
    echo "$content" | sed -n '/^---$/,/^---$/d;p' | sed '/^$/d'
}

migrate_agent() {
    local src="$1"
    local filename
    filename=$(basename "$src")
    local dest="$OPENCODE_AGENTS/$filename"

    log_verbose "Processing agent: $filename"

    # Skip symbolic links
    if [[ -L "$src" ]]; then
        log_verbose "Skipping symlink: $filename -> $(readlink "$src")"
        return 0
    fi

    if ! check_destination "$dest"; then
        return 0
    fi

    # Read the source file
    local content
    content=$(cat "$src")

    # Check if file has YAML frontmatter
    if [[ "$content" != ---* ]]; then
        log_warn "Agent $filename has no frontmatter, copying as-is"
        if [[ "$DRY_RUN" != "true" ]]; then
            log_verbose "cp \"$src\" \"$dest\""
            cp "$src" "$dest"
        fi
        ((AGENTS_MIGRATED++)) || true
        return 0
    fi

    # Extract fields from Claude Code format
    local cc_name cc_description cc_model body
    cc_name=$(extract_yaml_field "$content" "name")
    cc_description=$(extract_yaml_field "$content" "description")
    cc_model=$(extract_yaml_field "$content" "model")

    # Get the body content (system prompt)
    body=$(echo "$content" | awk '/^---$/{if(++n==2){p=1;next}}p')

    # Map model name
    local oc_model
    if [[ -n "$cc_model" ]]; then
        oc_model=$(map_model_name "$cc_model")
    else
        oc_model="anthropic/claude-sonnet-4-5"
    fi

    # Determine mode based on agent purpose
    local mode="subagent"
    # Language experts and specialized tools are typically subagents
    # Build/Plan style agents would be primary

    # Generate OpenCode agent file
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Create agent $filename with translated schema"
    else
        cat > "$dest" << EOF
---
description: ${cc_description:-Migrated from Claude Code}
mode: $mode
model: $oc_model
temperature: 0.1
tools:
  "*": true
permission:
  edit: allow
  bash: allow
  write: allow
---
$body
EOF
        log_success "Migrated agent: $filename"
    fi

    ((AGENTS_MIGRATED++)) || true
}

migrate_all_agents() {
    log_info "Migrating agents..."
    ensure_dir "$OPENCODE_AGENTS"

    if [[ ! -d "$CLAUDE_AGENTS" ]]; then
        log_warn "Claude Code agents directory not found: $CLAUDE_AGENTS"
        return
    fi

    local count=0
    for agent in "$CLAUDE_AGENTS"/*.md; do
        if [[ -f "$agent" ]]; then
            migrate_agent "$agent"
            ((count++)) || true
        fi
    done

    log_info "Processed $count agents"
}

# =============================================================================
# Skills Migration
# =============================================================================

migrate_skill() {
    local skill_dir="$1"
    local skill_name
    skill_name=$(basename "$skill_dir")
    local skill_file="$skill_dir/skill.md"

    log_verbose "Processing skill: $skill_name"

    # Skip symbolic links
    if [[ -L "$skill_dir" ]]; then
        log_verbose "Skipping symlink: $skill_name -> $(readlink "$skill_dir")"
        return 0
    fi

    if [[ ! -f "$skill_file" ]]; then
        log_warn "Skill $skill_name has no skill.md file"
        return 0
    fi

    # Read the skill file
    local content
    content=$(cat "$skill_file")

    # Skills in Claude Code are converted to agents in OpenCode
    # The skill content becomes the agent's system prompt
    local dest="$OPENCODE_AGENTS/${skill_name}-skill.md"

    if ! check_destination "$dest"; then
        return 0
    fi

    # Extract fields
    local cc_name cc_description body
    cc_name=$(extract_yaml_field "$content" "name")
    cc_description=$(extract_yaml_field "$content" "description")
    body=$(echo "$content" | awk '/^---$/{if(++n==2){p=1;next}}p')

    # Check for additional skill resources
    local has_resources=false
    local resources_note=""
    if [[ -d "$skill_dir" ]]; then
        local resource_count
        resource_count=$(find "$skill_dir" -type f ! -name "skill.md" ! -name ".*" 2>/dev/null | wc -l)
        if [[ "$resource_count" -gt 0 ]]; then
            has_resources=true
            resources_note="
## Note: Additional Resources

This skill had additional resource files that have been copied to:
\`~/.config/opencode/knowledge/${skill_name}/\`

You may need to update file references in the prompt above."

            # Copy resources to knowledge directory
            local knowledge_dest="$OPENCODE_KNOWLEDGE/$skill_name"
            if [[ "$DRY_RUN" != "true" ]]; then
                ensure_dir "$knowledge_dest"
                find "$skill_dir" -type f ! -name "skill.md" ! -name ".*" -exec cp {} "$knowledge_dest/" \;
                log_verbose "Copied skill resources to $knowledge_dest"
            else
                log_dry_run "Copy skill resources to $knowledge_dest"
            fi
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Convert skill $skill_name to agent"
    else
        cat > "$dest" << EOF
---
description: ${cc_description:-Skill migrated from Claude Code}
mode: subagent
model: anthropic/claude-sonnet-4-5
temperature: 0.1
tools:
  "*": true
permission:
  edit: allow
  bash: allow
  write: allow
---

# ${cc_name:-$skill_name} Skill

$body
$resources_note
EOF
        log_success "Migrated skill: $skill_name -> ${skill_name}-skill.md"
    fi

    ((SKILLS_MIGRATED++)) || true
}

migrate_all_skills() {
    log_info "Migrating skills..."
    ensure_dir "$OPENCODE_AGENTS"
    ensure_dir "$OPENCODE_KNOWLEDGE"

    if [[ ! -d "$CLAUDE_SKILLS" ]]; then
        log_warn "Claude Code skills directory not found: $CLAUDE_SKILLS"
        return
    fi

    local count=0
    for skill in "$CLAUDE_SKILLS"/*/; do
        if [[ -d "$skill" ]]; then
            migrate_skill "$skill"
            ((count++)) || true
        fi
    done

    log_info "Processed $count skills"
}

# =============================================================================
# Settings Migration
# =============================================================================

migrate_settings() {
    log_info "Migrating settings..."

    if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
        log_warn "Claude Code settings not found: $CLAUDE_SETTINGS"
        return
    fi

    # Check for hooks (we'll create a plugin for these)
    local cc_hooks
    cc_hooks=$(jq -r '.hooks // empty' "$CLAUDE_SETTINGS" 2>/dev/null || true)

    # Check if opencode.json already exists
    if [[ -f "$OPENCODE_SETTINGS" ]]; then
        log_info "opencode.json already exists - checking for MCP servers to add"

        # Check if MCP section exists
        local has_mcp
        has_mcp=$(jq -r '.mcp // empty' "$OPENCODE_SETTINGS" 2>/dev/null || true)

        if [[ -z "$has_mcp" ]] || [[ "$has_mcp" == "null" ]]; then
            log_info "Adding MCP servers to existing opencode.json"
            if [[ "$DRY_RUN" != "true" ]]; then
                # Add MCP section to existing config
                local tmp_file
                tmp_file=$(mktemp)
                jq '. + {
                    "mcp": {
                        "context7": {
                            "type": "local",
                            "command": ["npx", "-y", "@context7/mcp-server"],
                            "timeout": 10000
                        },
                        "sequential-thinking": {
                            "type": "local",
                            "command": ["npx", "-y", "@modelcontextprotocol/server-sequential-thinking"],
                            "timeout": 5000
                        }
                    }
                }' "$OPENCODE_SETTINGS" > "$tmp_file" && mv "$tmp_file" "$OPENCODE_SETTINGS"
                log_success "Added MCP servers to existing opencode.json"
            else
                log_dry_run "Add MCP servers to existing opencode.json"
            fi
        else
            log_info "opencode.json already has MCP configuration - skipping"
        fi
    else
        # Create new opencode.json
        local cc_model
        cc_model=$(jq -r '.model // "sonnet"' "$CLAUDE_SETTINGS" 2>/dev/null || echo "sonnet")
        local oc_model
        oc_model=$(map_model_name "$cc_model")

        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Create opencode.json"
        else
            cat > "$OPENCODE_SETTINGS" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "$oc_model",
  "permission": {
    "edit": "ask",
    "write": "ask",
    "bash": "ask"
  },
  "tools": {
    "*": true
  },
  "mcp": {
    "context7": {
      "type": "local",
      "command": ["npx", "-y", "@context7/mcp-server"],
      "timeout": 10000
    },
    "sequential-thinking": {
      "type": "local",
      "command": ["npx", "-y", "@modelcontextprotocol/server-sequential-thinking"],
      "timeout": 5000
    }
  }
}
EOF
            log_success "Created opencode.json"
        fi
    fi

    # If there are hooks, create the plugin
    if [[ -n "$cc_hooks" ]] && [[ "$cc_hooks" != "null" ]]; then
        create_hooks_plugin
    fi
}

# =============================================================================
# Hooks Plugin Creation
# =============================================================================

create_hooks_plugin() {
    log_info "Creating hooks plugin..."
    ensure_dir "$OPENCODE_PLUGINS"

    local plugin_file="$OPENCODE_PLUGINS/git-checkpoint.ts"

    if ! check_destination "$plugin_file"; then
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Create git-checkpoint.ts plugin"
        return 0
    fi

    # Copy the plugin from our template
    if [[ -f "$SCRIPT_DIR/templates/git-checkpoint.ts" ]]; then
        cp "$SCRIPT_DIR/templates/git-checkpoint.ts" "$plugin_file"
    else
        # Create inline if template doesn't exist
        cat > "$plugin_file" << 'EOF'
/**
 * Git Checkpoint Plugin for OpenCode
 *
 * Migrated from Claude Code hooks configuration.
 * Creates git checkpoints before and after file modifications.
 */

import { plugin, PluginContext } from "@opencode-ai/plugin"

// Tools that modify files
const FILE_MODIFYING_TOOLS = ['write', 'edit', 'multiedit', 'notebookedit']

export default plugin((ctx: PluginContext) => ({
  // Pre-tool checkpoint
  "tool.execute.before": async (event) => {
    const toolName = event.tool?.toLowerCase() ?? ''

    if (FILE_MODIFYING_TOOLS.some(t => toolName.includes(t))) {
      try {
        // Create checkpoint before modification
        const input = JSON.stringify({
          tool: event.tool,
          timestamp: new Date().toISOString(),
          phase: 'before'
        })

        await ctx.$`echo ${input} | git-ai checkpoint opencode --hook-input stdin`
        ctx.app.log({ level: 'info', message: `Pre-checkpoint created for ${event.tool}` })
      } catch (error) {
        // Don't fail the tool execution if checkpoint fails
        ctx.app.log({ level: 'warn', message: `Pre-checkpoint failed: ${error}` })
      }
    }
  },

  // Post-tool checkpoint
  "tool.execute.after": async (event) => {
    const toolName = event.tool?.toLowerCase() ?? ''

    if (FILE_MODIFYING_TOOLS.some(t => toolName.includes(t))) {
      try {
        // Create checkpoint after modification
        const input = JSON.stringify({
          tool: event.tool,
          timestamp: new Date().toISOString(),
          phase: 'after',
          success: event.success ?? true
        })

        await ctx.$`echo ${input} | git-ai checkpoint opencode --hook-input stdin`
        ctx.app.log({ level: 'info', message: `Post-checkpoint created for ${event.tool}` })
      } catch (error) {
        // Don't fail if checkpoint fails
        ctx.app.log({ level: 'warn', message: `Post-checkpoint failed: ${error}` })
      }
    }
  }
}))
EOF
    fi

    log_success "Created git-checkpoint.ts plugin"

    # Create package.json for the plugin if it doesn't exist
    local package_json="$OPENCODE_CONFIG/package.json"
    if [[ ! -f "$package_json" ]]; then
        cat > "$package_json" << 'EOF'
{
  "name": "opencode-plugins",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@opencode-ai/plugin": "latest"
  }
}
EOF
        log_success "Created package.json for plugins"
    fi
}

# =============================================================================
# Validation
# =============================================================================

validate_migration() {
    log_info "Validating migration..."

    local issues=0

    # Check commands directory
    if [[ -d "$OPENCODE_COMMANDS" ]]; then
        local cmd_count
        cmd_count=$(find "$OPENCODE_COMMANDS" -name "*.md" -type f 2>/dev/null | wc -l)
        log_info "Found $cmd_count migrated commands"
    else
        log_warn "Commands directory not created"
        ((issues++)) || true
    fi

    # Check agents directory
    if [[ -d "$OPENCODE_AGENTS" ]]; then
        local agent_count
        agent_count=$(find "$OPENCODE_AGENTS" -name "*.md" -type f 2>/dev/null | wc -l)
        log_info "Found $agent_count migrated agents"
    else
        log_warn "Agents directory not created"
        ((issues++)) || true
    fi

    # Check opencode.json
    if [[ -f "$OPENCODE_SETTINGS" ]]; then
        if jq empty "$OPENCODE_SETTINGS" 2>/dev/null; then
            log_success "opencode.json is valid JSON"
        else
            log_error "opencode.json is not valid JSON"
            ((issues++)) || true
        fi
    else
        log_warn "opencode.json not created"
        ((issues++)) || true
    fi

    # Check plugin
    if [[ -f "$OPENCODE_PLUGINS/git-checkpoint.ts" ]]; then
        log_success "Git checkpoint plugin created"
    else
        log_info "No hooks plugin created (no hooks in source config)"
    fi

    if [[ $issues -eq 0 ]]; then
        log_success "Validation passed!"
    else
        log_warn "Validation found $issues issues"
    fi
}

# =============================================================================
# Main
# =============================================================================

print_banner() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║           Claude Code → OpenCode Migration Script                 ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
}

print_summary() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "                         Migration Summary"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Commands migrated:  $COMMANDS_MIGRATED"
    echo "  Agents migrated:    $AGENTS_MIGRATED"
    echo "  Skills migrated:    $SKILLS_MIGRATED"
    echo "  Errors:             $ERRORS"
    echo ""
    echo "  Source:      $CLAUDE_CONFIG"
    echo "  Destination: $OPENCODE_CONFIG"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN - No changes were made]"
        echo ""
    fi

    if [[ $ERRORS -gt 0 ]]; then
        echo "  ⚠️  Migration completed with errors. Review the output above."
    else
        echo "  ✅ Migration completed successfully!"
    fi
    echo ""
}

print_next_steps() {
    if [[ "$DRY_RUN" != "true" ]] && [[ $ERRORS -eq 0 ]]; then
        echo "═══════════════════════════════════════════════════════════════════"
        echo "                           Next Steps"
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""
        echo "  1. Review the migrated configuration:"
        echo "     ls -la $OPENCODE_CONFIG/"
        echo ""
        echo "  2. Install plugin dependencies (if hooks were migrated):"
        echo "     cd $OPENCODE_CONFIG && bun install"
        echo ""
        echo "  3. Edit opencode.json to add your MCP servers:"
        echo "     $OPENCODE_SETTINGS"
        echo ""
        echo "  4. Test OpenCode:"
        echo "     opencode"
        echo ""
        echo "  5. Verify agents and commands work as expected"
        echo ""
        echo "  For manual adjustments, see the migration report at:"
        echo "  $OPENCODE_CONFIG/MIGRATION_LOG.md"
        echo ""
    fi
}

create_migration_log() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return
    fi

    local log_file="$OPENCODE_CONFIG/MIGRATION_LOG.md"

    cat > "$log_file" << EOF
# Claude Code to OpenCode Migration Log

**Migration Date:** $(date -Iseconds)
**Source:** $CLAUDE_CONFIG
**Destination:** $OPENCODE_CONFIG

## Summary

- **Commands Migrated:** $COMMANDS_MIGRATED
- **Agents Migrated:** $AGENTS_MIGRATED
- **Skills Migrated:** $SKILLS_MIGRATED
- **Errors:** $ERRORS

## Manual Steps Required

### 1. MCP Server Configuration

Your Claude Code MCP servers need to be manually configured in \`opencode.json\`.

Add your MCP servers under the \`"mcp"\` key:

\`\`\`json
{
  "mcp": {
    "server-name": {
      "type": "local",
      "command": ["npx", "-y", "your-mcp-package"],
      "timeout": 5000
    }
  }
}
\`\`\`

Common MCP servers to configure:
- perplexity (web search)
- nixos (NixOS package search)
- pal (multi-model consensus)
- notion (document queries)

### 2. Plugin Dependencies

If you had hooks configured, run:

\`\`\`bash
cd $OPENCODE_CONFIG
bun install
\`\`\`

### 3. Skill Resources

Skills with additional files (CSV, TXT, etc.) have been copied to:
\`$OPENCODE_KNOWLEDGE/\`

You may need to update file references in the converted agent prompts.

### 4. Model Names

The following model mappings were applied:
- \`opus\` → \`anthropic/claude-opus-4-5\`
- \`sonnet\` → \`anthropic/claude-sonnet-4-5\`
- \`haiku\` → \`anthropic/claude-haiku-4-5\`

### 5. Agent Permissions

All migrated agents have default permissions:
- \`mode: subagent\`
- \`permission: { edit: allow, bash: allow, write: allow }\`

Adjust these based on each agent's actual needs.

## Files Created

### Commands
$(find "$OPENCODE_COMMANDS" -name "*.md" -type f 2>/dev/null | sort | sed 's|^|- |')

### Agents
$(find "$OPENCODE_AGENTS" -name "*.md" -type f 2>/dev/null | sort | sed 's|^|- |')

### Plugins
$(find "$OPENCODE_PLUGINS" -name "*.ts" -type f 2>/dev/null | sort | sed 's|^|- |')

### Configuration
- $OPENCODE_SETTINGS

---

*Generated by migrate.sh*
EOF

    log_success "Created migration log: $log_file"
}

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Migrate Claude Code configuration to OpenCode format.

Options:
  --dry-run     Show what would be done without making changes
  --force       Overwrite existing files in destination
  --verbose     Show detailed output
  --help        Show this help message

Environment Variables:
  CLAUDE_CONFIG    Source config directory (default: ~/.config/claude)
  OPENCODE_CONFIG  Destination config directory (default: ~/.config/opencode)

Examples:
  $(basename "$0") --dry-run          # Preview migration
  $(basename "$0") --verbose          # Migrate with detailed output
  $(basename "$0") --force --verbose  # Overwrite existing and show details
EOF
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    print_banner

    log_info "Starting migration..."
    log_info "Source (read-only): $CLAUDE_CONFIG"
    log_info "Destination: $OPENCODE_CONFIG"

    # Safety check: validate paths before proceeding
    validate_paths

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY RUN mode - no changes will be made"
    fi

    if [[ "$FORCE" != "true" ]]; then
        log_info "Only creating NEW files (use --force to overwrite existing)"
    fi

    echo ""

    # Create base directory
    ensure_dir "$OPENCODE_CONFIG"

    # Run migrations
    migrate_all_commands
    echo ""
    migrate_all_agents
    echo ""
    migrate_all_skills
    echo ""
    migrate_settings
    echo ""

    # Validate
    if [[ "$DRY_RUN" != "true" ]]; then
        validate_migration
        create_migration_log
    fi

    print_summary
    print_next_steps

    exit $ERRORS
}

main "$@"
