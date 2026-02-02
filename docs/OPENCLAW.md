# OpenClaw Usage Guide

This guide explains how to use OpenClaw after installing it via the Nix derivation on your macOS system.

## Overview

OpenClaw is an open-source, self-hosted AI assistant that runs locally and executes real tasks on your computer. Unlike traditional chatbots, OpenClaw functions as an autonomous agent that can interact with your operating system, file system, and applications.

You interact with OpenClaw through:
- Terminal UI (TUI)
- Web dashboard
- Messaging platforms (WhatsApp, Telegram, Discord, etc.)

## Installation

### Step 1: Switch to Your New Nix Configuration

```bash
./build system  # Test the build first (ALWAYS do this)
u switch        # Apply the changes to your system
```

After switching, `openclaw` will be available in your PATH.

### Step 2: Verify Installation

```bash
openclaw --version
```

Expected output: `2026.1.30`

## Initial Setup

### Running Onboarding (One-Time Setup)

The onboarding process is required before you can use OpenClaw. Run:

```bash
openclaw onboard --install-daemon
```

The `--install-daemon` flag sets up OpenClaw to run continuously in the background (24/7 operation).

### Onboarding Wizard Steps

During onboarding, you'll be prompted for the following:

#### 1. Select Mode
- Choose **QuickStart** (press spacebar, then enter)
- This applies safe defaults for most settings
- Advanced users can choose Custom mode for more control

#### 2. Choose AI Provider/Model
Select your preferred AI provider:

- **Anthropic** (Recommended if you have a Claude API key)
  - Requires Anthropic API key
  - Models: Claude Sonnet, Opus, Haiku

- **OpenAI**
  - Requires OpenAI API key
  - Models: GPT-4, GPT-3.5-turbo, etc.

- **Google Gemini**
  - OAuth authentication or API key
  - Models: Gemini Pro, Gemini Flash

- **Other providers**: Ollama (local), OpenRouter, etc.

**Note**: You'll need to provide your API key when prompted.

#### 3. Connect Messaging Platforms (Optional)

You can connect OpenClaw to messaging platforms for remote access:

**WhatsApp**:
- Scan the QR code with your phone
- OpenClaw will be available as a contact

**Telegram**:
1. Open Telegram and search for `@BotFather`
2. Send `/newbot` and follow the prompts
3. Copy the bot token
4. Paste the token when OpenClaw asks for it

**Discord, Slack, Signal, etc.**:
- Follow the platform-specific prompts
- You can configure these later via `openclaw configure --section channels`

**Skip if not needed**: You can skip this during initial setup and add messaging platforms later.

#### 4. Web Search Configuration (Optional)

Configure web search capabilities:
- **Brave Search API**: Provide API key for web search
- Can skip and configure later via `openclaw configure --section web`

#### 5. Skills Setup (Optional)

Skills extend OpenClaw's capabilities (email, calendar, etc.):
- Select "Yes" to enable skills
- Choose package manager: **npm** (recommended)
- Can "Skip for now" and add skills later

### Configuration Files

After onboarding, OpenClaw creates configuration in:

```
~/.openclaw/
├── config.json       # Main configuration
├── gateway/          # Gateway settings
├── channels/         # Messaging platform configs
└── data/             # Conversation history, cache
```

## Accessing OpenClaw

### Terminal UI (TUI)

Launch the interactive terminal interface:

```bash
openclaw        # Launch TUI
# or
openclaw tui    # Explicit TUI command
```

In the TUI, you can:
- Chat directly with OpenClaw
- Execute commands and tasks
- View conversation history
- Navigate with arrow keys and keyboard shortcuts

**TUI Commands**:
- Type naturally to chat with OpenClaw
- `Ctrl+C` or type `exit` to quit
- Use arrow keys to navigate history

### Web Dashboard (Control UI)

During onboarding, OpenClaw provides a web UI URL:

```
Web UI: http://localhost:3001
```

Open this URL in your browser to access:
- **Dashboard**: System status and metrics
- **Conversations**: View and search chat history
- **Settings**: Configure AI providers, channels, skills
- **Logs**: Real-time log viewer
- **Status**: Health checks and diagnostics

### Messaging Apps

Once you've connected messaging platforms during onboarding, send messages directly:

**Example (WhatsApp/Telegram)**:
```
Organize my downloads folder by file type
```

```
Send an email to john@example.com with subject "Meeting Tomorrow"
```

```
What's the weather forecast for today?
```

OpenClaw will respond and execute tasks through the messaging app.

## Common Commands

### Status and Health

```bash
# Comprehensive status report (read-only, safe to share)
openclaw status --all

# Health check
openclaw health

# Deep diagnostics (queries running gateway)
openclaw status --deep

# View logs
openclaw logs
```

### Gateway Management

```bash
# Start the gateway (if not running)
openclaw gateway run

# Stop the gateway
openclaw stop

# Restart the gateway
openclaw restart

# Gateway status
openclaw gateway status
```

### Configuration

```bash
# Re-run onboarding wizard
openclaw onboard

# Configure web search
openclaw configure --section web

# Configure messaging channels
openclaw configure --section channels

# Configure AI models
openclaw configure --section models

# View current configuration
openclaw config show
```

### Development Mode

```bash
# Run in development mode (for debugging)
OPENCLAW_PROFILE=dev openclaw tui

# Skip channels during development
OPENCLAW_SKIP_CHANNELS=1 openclaw gateway
```

## Usage Examples

### File Management

```
Move all PDFs from my Downloads folder to Documents/PDFs
```

```
Find duplicate files in my home directory
```

```
Compress all images in the current folder
```

### System Operations

```
Show me disk usage for my home directory
```

```
List all processes using more than 1GB of memory
```

```
Check if port 3000 is in use
```

### Automation and Monitoring

```
Monitor my Downloads folder and organize new files by type daily at 9 AM
```

```
Remind me to check emails every hour during work hours
```

```
Watch this log file and alert me if errors appear
```

### Development Tasks

```
Create a new Node.js project with TypeScript setup
```

```
Run the tests in the current directory
```

```
Find all TODO comments in this codebase
```

### Web and Research

```
Search for the latest React documentation
```

```
Find articles about Nix package management published this week
```

```
Summarize this webpage: https://example.com/article
```

## Advanced Usage

### Custom Skills

OpenClaw supports custom skills for extending functionality:

1. **Install a skill**:
   ```bash
   openclaw skill install <skill-name>
   ```

2. **List installed skills**:
   ```bash
   openclaw skill list
   ```

3. **Remove a skill**:
   ```bash
   openclaw skill remove <skill-name>
   ```

### API Access

OpenClaw can be accessed programmatically via its API:

```bash
# Run OpenClaw in RPC mode
openclaw agent --mode rpc --json
```

This allows integration with other tools and scripts.

### Multiple Profiles

You can run multiple OpenClaw instances with different profiles:

```bash
# Set profile via environment variable
OPENCLAW_PROFILE=work openclaw tui

# Or use the --profile flag
openclaw tui --profile work
```

## Nix-Specific Notes

### Playwright Browser Automation

The Nix build disables Playwright browser downloads to maintain reproducibility. If you need browser automation:

1. **Manual browser installation**:
   ```bash
   # Install Playwright browsers separately
   npx playwright install chromium
   ```

2. **Set browser path** (if using Nix-managed Chromium):
   ```bash
   export PLAYWRIGHT_BROWSERS_PATH=/path/to/nix/chromium
   ```

### Daemon Management

On macOS, the `--install-daemon` flag sets up a LaunchAgent:

```bash
# Check if daemon is running
ps aux | grep openclaw

# LaunchAgent location (if using standard macOS setup)
~/Library/LaunchAgents/ai.openclaw.plist
```

### Updating OpenClaw

To update to a newer version:

1. Edit `overlays/30-openclaw.nix`:
   ```nix
   version = "2026.2.1";  # New version
   ```

2. Update the source hash:
   ```bash
   # Use fake hash first
   hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
   ```

3. Build to get real hash:
   ```bash
   ./build system  # Error will show correct hash
   ```

4. Update both `hash` and `pnpmDepsHash` with correct values

5. Rebuild and switch:
   ```bash
   ./build system
   u switch
   ```

## Troubleshooting

### OpenClaw Won't Start

```bash
# Check status
openclaw status --all

# Check logs for errors
openclaw logs

# Verify installation
openclaw --version

# Re-run onboarding
openclaw onboard
```

### Gateway Connection Issues

```bash
# Check if gateway is running
openclaw health

# Restart gateway
openclaw restart

# Check gateway logs
openclaw logs --gateway
```

### Messaging Platform Not Working

```bash
# Reconfigure channels
openclaw configure --section channels

# Check channel status
openclaw status --deep

# View channel-specific logs
openclaw logs --channel whatsapp
```

### High Memory Usage

```bash
# Check resource usage
openclaw status --all

# Reduce concurrent operations in config
nano ~/.openclaw/config.json
```

### Permission Errors

```bash
# Ensure OpenClaw has necessary permissions
ls -la ~/.openclaw

# Fix permissions if needed
chmod -R 755 ~/.openclaw

# On macOS, grant Full Disk Access in System Preferences
# System Preferences > Security & Privacy > Privacy > Full Disk Access
```

### API Key Issues

```bash
# Reconfigure AI provider
openclaw configure --section models

# Or re-run onboarding
openclaw onboard
```

## Example First Session

Here's a complete example of getting started:

```bash
# 1. Switch to new Nix configuration
cd ~/src/nix
./build system
u switch

# 2. Verify installation
openclaw --version
# Output: 2026.1.30

# 3. Run onboarding
openclaw onboard --install-daemon
# Follow prompts:
# - Select QuickStart
# - Choose Anthropic (enter API key)
# - Connect Telegram (optional)
# - Skip web search for now
# - Skip skills for now

# 4. Launch TUI to test
openclaw tui

# In the TUI, try these commands:
> Hello! Can you help me organize my files?
> What can you do?
> List files in my Downloads folder
> Show me my system information

# 5. Exit TUI (Ctrl+C) and check status
openclaw status --all

# 6. Open web dashboard
open http://localhost:3001

# 7. Test via messaging (if configured)
# Send a message via WhatsApp/Telegram:
# "What's the weather today?"
```

## Best Practices

### Security

1. **API Keys**: Store API keys securely, never commit to version control
2. **Permissions**: Only grant necessary system permissions
3. **Network**: Be cautious when exposing OpenClaw to the internet
4. **Skills**: Review skill code before installation

### Performance

1. **Resource Limits**: Monitor memory/CPU usage with `openclaw status`
2. **Conversation History**: Periodically clean old conversations
3. **Logs**: Rotate logs to prevent disk space issues

### Reliability

1. **Regular Updates**: Keep OpenClaw updated for bug fixes
2. **Backups**: Back up `~/.openclaw/config.json` regularly
3. **Testing**: Test critical automations before relying on them
4. **Monitoring**: Set up alerts for gateway downtime

## Additional Resources

- **Official Documentation**: https://docs.openclaw.ai
- **GitHub Repository**: https://github.com/openclaw/openclaw
- **Community Discord**: Join via OpenClaw website
- **Nix Overlay**: `~/src/nix/overlays/30-openclaw.nix`

## Quick Reference

| Command | Description |
|---------|-------------|
| `openclaw` | Launch TUI |
| `openclaw --version` | Show version |
| `openclaw onboard` | Run onboarding wizard |
| `openclaw status --all` | Comprehensive status |
| `openclaw health` | Health check |
| `openclaw logs` | View logs |
| `openclaw restart` | Restart gateway |
| `openclaw configure --section <name>` | Configure section |
| `openclaw tui` | Launch terminal UI |
| `openclaw gateway run` | Start gateway |

---

**Need Help?**
- Run `openclaw --help` for command-line options
- Check logs: `openclaw logs`
- Review status: `openclaw status --all`
- Re-run onboarding: `openclaw onboard`
