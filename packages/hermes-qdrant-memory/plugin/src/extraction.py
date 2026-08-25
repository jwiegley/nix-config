import json
import logging
from typing import Any, Dict, List

logger = logging.getLogger(__name__)

PROMPT = """From this conversation, extract facts worth remembering in future sessions.
Return JSON:
{"facts": [{"content": "...", "category": "...", "tags": ["..."]}]}

  content   - one self-contained fact, understandable without the conversation.
              Name the subject, no bare "it"/"they"/"this"
  category  - preference (likes/dislikes/style), entity (person/system/thing),
              event (something that happened), case (a specific decision/incident),
              pattern (recurring behavior), or general
  tags      - a few short lowercase search keywords
  abstract  - optional. Only when content is long, a one-line summary

Record only durable workspace knowledge. Skip trivia, chit-chat, and anything
true only for this session. If nothing qualifies, return {"facts": []}."""

VALID_CATEGORIES = {"preference", "entity", "event", "case", "pattern", "general"}


def _response_text(response: Any) -> str:
    # call_llm returns whatever the SDK gives: OpenAI ChatCompletion
    # (.choices[0].message.content), Anthropic (.content is a list of blocks),
    # a bare .content string, or a plain string.
    choices = getattr(response, "choices", None)
    if choices:
        content = getattr(getattr(choices[0], "message", None), "content", None)
    else:
        content = getattr(response, "content", response)
    if isinstance(content, list):  # content parts / Anthropic blocks
        return "".join(
            getattr(b, "text", None) or (b.get("text", "") if isinstance(b, dict) else "")
            for b in content
        )
    return content if isinstance(content, str) else str(content)


def _parse_json_object(text: str) -> Dict[str, Any] | None:
    # Models often wrap JSON in prose or ```json fences and don't honor a
    # response_format flag. Try strict parse, then the first {...} span.
    text = text.strip()
    try:
        obj = json.loads(text)
        return obj if isinstance(obj, dict) else None
    except Exception:
        pass
    start, end = text.find("{"), text.rfind("}")
    if start == -1 or end <= start:
        return None
    try:
        obj = json.loads(text[start : end + 1])
        return obj if isinstance(obj, dict) else None
    except Exception:
        return None


def format_messages(messages: List[Dict[str, Any]]) -> str:
    lines = []
    for message in messages:
        role = message.get("role", "")
        if role not in {"user", "assistant"}:
            continue
        content = str(message.get("content") or "").strip()
        if not content:
            continue
        lines.append(f"{role}: {content}")
    return "\n\n".join(lines)


def extract(
    messages: List[Dict[str, Any]], context: Dict[str, Any] | None = None
) -> list[dict[str, Any]]:
    """Extract durable facts using Hermes's auxiliary LLM client."""
    if not messages:
        return []
    try:
        from agent.auxiliary_client import call_llm
    except Exception as exc:
        logger.debug(
            "auxiliary client unavailable for qdrant extraction (%s)",
            type(exc).__name__,
        )
        return []

    try:
        response = call_llm(
            task="qdrant_extraction",
            messages=[
                {"role": "system", "content": PROMPT},
                {"role": "user", "content": format_messages(messages)},
            ],
            timeout=30,
        )
    except Exception as exc:
        logger.debug("qdrant extraction call failed (%s)", type(exc).__name__)
        return []

    text = _response_text(response)
    payload = _parse_json_object(text)
    if payload is None:
        logger.debug("qdrant extraction returned non-json")
        return []

    facts = payload.get("facts")
    if not isinstance(facts, list):
        return []
    cleaned = []
    for fact in facts:
        if not isinstance(fact, dict):
            continue
        content = str(fact.get("content") or "").strip()
        if not content:
            continue
        category = str(fact.get("category") or "general").strip()
        tags = fact.get("tags") if isinstance(fact.get("tags"), list) else []
        cleaned.append(
            {
                "content": content,
                "abstract": str(fact.get("abstract") or "").strip(),
                "category": category if category in VALID_CATEGORIES else "general",
                "tags": [s for t in tags if (s := str(t).strip())],
            }
        )
    return cleaned
