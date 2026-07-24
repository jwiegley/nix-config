import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

export const SAFETY_TOKENS = 16_384;
export const RETRY_GROWTH_TOKENS = 8_192;

const CONTINUATION_MESSAGE =
  "Context handling interrupted work that is still in progress. Continue the original user request immediately. Do not ask for confirmation or merely report status; proceed with the next unfinished action unless genuine user input is required.";

export function calculateThreshold(contextWindow: number, maxTokens: number): number {
  return Math.max(SAFETY_TOKENS, contextWindow - Math.max(0, maxTokens) - SAFETY_TOKENS);
}

function continuationReason(message: unknown): "length" | "tool" | null {
  if (!message || typeof message !== "object") return null;

  const assistant = message as {
    role?: string;
    stopReason?: string;
    content?: Array<{ type?: string }>;
  };

  if (assistant.role !== "assistant") return null;
  if (assistant.stopReason === "length") return "length";
  if (assistant.content?.some((part) => part.type === "toolCall")) return "tool";
  return null;
}

function isTerminalCompactionError(error: unknown): boolean {
  const name = error instanceof Error ? error.name : "";
  const message = error instanceof Error ? error.message : String(error);

  return (
    name === "AbortError" ||
    /\b(?:abort(?:ed)?|cancel(?:led|ed))\b/i.test(message) ||
    /\b(?:authentication|credentials?|unauthori[sz]ed|forbidden)\b/i.test(message) ||
    /\b(?:api[ -]?key|billing|payment required|insufficient quota)\b/i.test(message) ||
    /\b(?:401|403)\b/.test(message) ||
    /\bno model (?:is )?(?:selected|configured)\b/i.test(message)
  );
}

function sessionEndsAtCompaction(ctx: ExtensionContext): boolean {
  const branch = ctx.sessionManager.getBranch();
  return branch.length > 0 && branch[branch.length - 1]?.type === "compaction";
}

export default function autoCompactResume(pi: ExtensionAPI) {
  let compacting = false;
  let continuationQueued = false;
  let deferCompactionUntil = 0;

  function queueContinuation() {
    if (continuationQueued) return;
    continuationQueued = true;

    pi.sendMessage(
      {
        customType: "auto-compact-resume",
        content: CONTINUATION_MESSAGE,
        display: false,
        details: { automatic: true },
      },
      { triggerTurn: true, deliverAs: "followUp" },
    );
  }

  function compactIfNeeded(ctx: ExtensionContext, resume: boolean): boolean {
    if (compacting) return true;

    const usage = ctx.getContextUsage();
    const maxTokens = ctx.model?.maxTokens ?? 0;
    if (usage?.tokens == null || maxTokens <= 0) return false;
    if (usage.tokens < deferCompactionUntil) return false;
    if (usage.tokens < calculateThreshold(usage.contextWindow, maxTokens)) return false;

    compacting = true;
    ctx.compact({
      customInstructions:
        "Preserve the active goal, completed work, pending work, modified files, errors, and exact next action so work can resume immediately.",
      onComplete: () => {
        compacting = false;
        deferCompactionUntil = 0;
        if (resume) queueContinuation();
      },
      onError: (error) => {
        compacting = false;
        const failedUsage = ctx.getContextUsage();
        if (failedUsage?.tokens != null) {
          deferCompactionUntil = failedUsage.tokens + RETRY_GROWTH_TOKENS;
        }
        if (resume && !isTerminalCompactionError(error)) queueContinuation();
      },
    });
    return true;
  }

  pi.on("session_start", (_event, ctx) => {
    compacting = false;
    continuationQueued = false;
    deferCompactionUntil = 0;
    if (!sessionEndsAtCompaction(ctx)) compactIfNeeded(ctx, false);
  });

  pi.on("turn_start", () => {
    continuationQueued = false;
  });

  pi.on("session_compact", () => {
    compacting = false;
    deferCompactionUntil = 0;
  });

  pi.on("turn_end", (event, ctx) => {
    const reason = continuationReason(event.message);
    const compactionStarted = compactIfNeeded(ctx, reason !== null);

    if (reason === "length" && !compactionStarted) queueContinuation();
  });
}
