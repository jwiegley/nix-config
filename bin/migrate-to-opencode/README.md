# Claude Code to OpenCode Migration Tools

This directory contains scripts and templates for migrating your Claude Code configuration to OpenCode.

## Quick Start

```bash
# Preview what will be migrated (no changes made)
./migrate.sh --dry-run

# Run the migration
./migrate.sh --verbose

# Validate the result
./validate.sh
```

## What Gets Migrated

| Claude Code | OpenCode | Notes |
|-------------|----------|-------|
| `~/.config/claude/commands/*.md` | `~/.config/opencode/command/*.md` | Frontmatter added if missing |
| `~/.config/claude/agents/*.md` | `~/.config/opencode/agent/*.md` | Schema translated |
| `~/.config/claude/skills/*/skill.md` | `~/.config/opencode/agent/*-skill.md` | Converted to agents |
| `~/.config/claude/settings.json` | `~/.config/opencode/opencode.json` | Manual MCP config needed |
| hooks in settings.json | `~/.config/opencode/plugin/*.ts` | TypeScript plugin created |

## Files

### Scripts

- **`migrate.sh`** - Main migration script
- **`validate.sh`** - Validate migrated configuration

### Templates

- **`templates/git-checkpoint.ts`** - TypeScript plugin for git checkpoint hooks
- **`templates/package.json`** - npm package configuration for plugins
- **`templates/opencode.json.example`** - Example configuration with all MCP servers

## Migration Options

```bash
./migrate.sh [OPTIONS]

Options:
  --dry-run     Show what would be done without making changes
  --force       Overwrite existing files in destination
  --verbose     Show detailed output
  --help        Show help message

Environment Variables:
  CLAUDE_CONFIG    Source directory (default: ~/.config/claude)
  OPENCODE_CONFIG  Destination directory (default: ~/.config/opencode)
```

## Post-Migration Steps

### 1. Install Plugin Dependencies

If you had hooks configured:

```bash
cd ~/.config/opencode
bun install
```

### 2. Configure MCP Servers

Edit `~/.config/opencode/opencode.json` to add your MCP servers. See `templates/opencode.json.example` for a complete example.

Common servers to configure:
- `context7` - Project context
- `perplexity` - Web search
- `nixos` - NixOS package/option search
- `pal` - Multi-model consensus

### 3. Review Agent Permissions

All migrated agents have default permissions. Review and adjust:

```yaml
permission:
  edit: allow   # or ask, deny
  bash: allow   # or ask, deny
  write: allow  # or ask, deny
```

### 4. Validate

```bash
./validate.sh
```

### 5. Test

```bash
opencode
```

## Schema Translation

### Model Names

| Claude Code | OpenCode |
|-------------|----------|
| `opus` | `anthropic/claude-opus-4-5` |
| `sonnet` | `anthropic/claude-sonnet-4-5` |
| `haiku` | `anthropic/claude-haiku-4-5` |

### Agent Frontmatter

Claude Code:
```yaml
---
name: my-agent
description: Agent description
model: sonnet
---
```

OpenCode:
```yaml
---
description: Agent description
mode: subagent
model: anthropic/claude-sonnet-4-5
temperature: 0.1
tools:
  "*": true
permission:
  edit: allow
  bash: allow
---
```

### Command Frontmatter

Claude Code commands often have no frontmatter. OpenCode requires at least a description:

```yaml
---
description: Brief description of what the command does
---

Command content here...
```

## Troubleshooting

### "opencode: command not found"

Install OpenCode first:
```bash
npm install -g opencode
# or
bun install -g opencode
```

### Plugin errors

Ensure dependencies are installed:
```bash
cd ~/.config/opencode
bun install
```

### MCP server connection errors

Check that:
1. The MCP server package is installed
2. Required environment variables are set
3. API keys are valid

### Model not available

Ensure you have API access to the model. OpenCode supports 75+ models via various providers.

## Files Created by Migration

```
~/.config/opencode/
├── opencode.json           # Main configuration
├── package.json            # Plugin dependencies (if hooks migrated)
├── MIGRATION_LOG.md        # Detailed migration log
├── command/                # Slash commands
│   ├── heavy.md
│   ├── fix-github-issue.md
│   └── ...
├── agent/                  # Custom agents
│   ├── nix-pro.md
│   ├── haskell-pro.md
│   ├── nixos-skill.md      # Converted from skill
│   └── ...
├── plugin/                 # TypeScript plugins (if hooks migrated)
│   └── git-checkpoint.ts
└── knowledge/              # Skill resources (if any)
    └── persian/
        └── TERMS.csv
```

## Support

- OpenCode docs: https://opencode.ai/docs/
- OpenCode config: https://opencode.ai/docs/config/
- OpenCode agents: https://opencode.ai/docs/agents/
- OpenCode plugins: https://opencode.ai/docs/plugins/
