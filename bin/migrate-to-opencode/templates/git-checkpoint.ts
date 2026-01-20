/**
 * Git Checkpoint Plugin for OpenCode
 *
 * Migrated from Claude Code hooks configuration.
 * Creates git checkpoints before and after file modifications.
 *
 * This plugin replicates the behavior of Claude Code's PreToolUse and PostToolUse
 * hooks that ran `git-ai checkpoint claude --hook-input stdin` for file operations.
 *
 * Installation:
 *   1. Copy this file to ~/.config/opencode/plugin/git-checkpoint.ts
 *   2. Ensure @opencode-ai/plugin is in your package.json
 *   3. Run `bun install` in ~/.config/opencode/
 *
 * Configuration:
 *   The plugin automatically checkpoints before/after these tools:
 *   - write (file creation)
 *   - edit (file modification)
 *   - multiedit (multiple file modifications)
 *   - notebookedit (Jupyter notebook modifications)
 *
 * Requirements:
 *   - git-ai must be installed and available in PATH
 *   - The working directory must be a git repository
 */

import { plugin, PluginContext } from "@opencode-ai/plugin"

// Configuration
const CONFIG = {
  // Tools that modify files and should trigger checkpoints
  fileModifyingTools: ['write', 'edit', 'multiedit', 'notebookedit'],

  // Command to run for checkpointing
  checkpointCommand: 'git-ai',
  checkpointArgs: ['checkpoint', 'opencode', '--hook-input', 'stdin'],

  // Whether to fail the tool execution if checkpoint fails
  failOnCheckpointError: false,

  // Enable debug logging
  debug: false,
}

interface CheckpointInput {
  tool: string
  timestamp: string
  phase: 'before' | 'after'
  file?: string
  success?: boolean
  error?: string
}

/**
 * Check if a tool name matches our list of file-modifying tools
 */
function isFileModifyingTool(toolName: string): boolean {
  const normalized = toolName.toLowerCase()
  return CONFIG.fileModifyingTools.some(t => normalized.includes(t))
}

/**
 * Create a checkpoint with the given input data
 */
async function createCheckpoint(
  ctx: PluginContext,
  input: CheckpointInput
): Promise<void> {
  const inputJson = JSON.stringify(input)

  if (CONFIG.debug) {
    ctx.app.log({
      level: 'debug',
      message: `Creating checkpoint: ${inputJson}`
    })
  }

  try {
    // Use Bun's shell to pipe input to the checkpoint command
    const result = await ctx.$`echo ${inputJson} | ${CONFIG.checkpointCommand} ${CONFIG.checkpointArgs.join(' ')}`

    ctx.app.log({
      level: 'info',
      message: `Checkpoint created (${input.phase}): ${input.tool}`
    })
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error)

    ctx.app.log({
      level: 'warn',
      message: `Checkpoint failed (${input.phase}): ${errorMessage}`
    })

    if (CONFIG.failOnCheckpointError) {
      throw error
    }
  }
}

/**
 * Main plugin export
 */
export default plugin((ctx: PluginContext) => {
  ctx.app.log({
    level: 'info',
    message: 'Git checkpoint plugin loaded'
  })

  return {
    /**
     * Pre-tool execution hook
     * Creates a checkpoint before file-modifying tools run
     */
    "tool.execute.before": async (event) => {
      const toolName = event.tool ?? ''

      if (!isFileModifyingTool(toolName)) {
        return
      }

      await createCheckpoint(ctx, {
        tool: toolName,
        timestamp: new Date().toISOString(),
        phase: 'before',
        file: event.args?.file_path ?? event.args?.path,
      })
    },

    /**
     * Post-tool execution hook
     * Creates a checkpoint after file-modifying tools complete
     */
    "tool.execute.after": async (event) => {
      const toolName = event.tool ?? ''

      if (!isFileModifyingTool(toolName)) {
        return
      }

      await createCheckpoint(ctx, {
        tool: toolName,
        timestamp: new Date().toISOString(),
        phase: 'after',
        file: event.args?.file_path ?? event.args?.path,
        success: event.success ?? true,
        error: event.error?.message,
      })
    },

    /**
     * Session idle hook (optional)
     * Could be used for periodic checkpoints during long sessions
     */
    "session.idle": async () => {
      if (CONFIG.debug) {
        ctx.app.log({
          level: 'debug',
          message: 'Session idle - checkpoint plugin active'
        })
      }
    },
  }
})
