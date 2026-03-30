#!/usr/bin/env python3
"""Ollama LLM bridge — thin wrapper around the local Ollama HTTP API.

All public functions gracefully return *None* when Ollama is unreachable so
callers can fall back to rule-based logic without try/except boilerplate.
"""
from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from typing import Any
from urllib import error, request

_AVAILABLE_CACHE: bool | None = None
_AVAILABLE_CACHE_MODEL: str = ""


@dataclass
class LLMConfig:
    enabled: bool = False
    provider: str = "ollama"
    base_url: str = "http://localhost:11434"
    model: str = "llama3.2:3b"
    temperature: float = 0.3
    timeout_seconds: int = 30
    smart_classify: bool = True
    smart_reply: bool = True
    smart_summary: bool = True
    vault_questions: bool = True
    #: Единый стиль заголовка «(Идея|Мысль|Пост) …» + развёрнутое тело при маршрутизации сигналов.
    vault_note_format: bool = True


def load_llm_config(raw: dict[str, Any] | None) -> LLMConfig:
    if not raw or not isinstance(raw, dict):
        return LLMConfig()
    if "vault_note_format" in raw:
        vault_fmt = bool(raw["vault_note_format"])
    else:
        vault_fmt = bool(raw.get("idea_elaborate", True))
    return LLMConfig(
        enabled=bool(raw.get("enabled", False)),
        provider=str(raw.get("provider", "ollama")),
        base_url=str(raw.get("base_url", "http://localhost:11434")).rstrip("/"),
        model=str(raw.get("model", "llama3.2:3b")),
        temperature=float(raw.get("temperature", 0.3)),
        timeout_seconds=int(raw.get("timeout_seconds", 30)),
        smart_classify=bool(raw.get("smart_classify", True)),
        smart_reply=bool(raw.get("smart_reply", True)),
        smart_summary=bool(raw.get("smart_summary", True)),
        vault_questions=bool(raw.get("vault_questions", True)),
        vault_note_format=vault_fmt,
    )


# ---------------------------------------------------------------------------
# Low-level API
# ---------------------------------------------------------------------------

def ollama_available(cfg: LLMConfig) -> bool:
    """Return True if the Ollama server is reachable and the model is loaded."""
    global _AVAILABLE_CACHE, _AVAILABLE_CACHE_MODEL
    # Only cache positive results so a later `ollama pull` is picked up without bot restart (H1).
    if _AVAILABLE_CACHE is True and _AVAILABLE_CACHE_MODEL == cfg.model:
        return True

    if not cfg.enabled:
        return False
    try:
        req = request.Request(f"{cfg.base_url}/api/tags", method="GET")
        with request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read())
        names = [m.get("name", "") for m in data.get("models", [])]
        found = any(cfg.model in n for n in names)
        if found:
            _AVAILABLE_CACHE = True
            _AVAILABLE_CACHE_MODEL = cfg.model
        return found
    except Exception:
        return False


def reset_availability_cache() -> None:
    global _AVAILABLE_CACHE, _AVAILABLE_CACHE_MODEL
    _AVAILABLE_CACHE = None
    _AVAILABLE_CACHE_MODEL = ""


def ollama_chat(
    cfg: LLMConfig,
    messages: list[dict[str, str]],
    *,
    temperature: float | None = None,
    max_tokens: int = 512,
) -> str | None:
    """Send a chat completion request. Returns the assistant text or None on failure."""
    if not ollama_available(cfg):
        return None
    payload = {
        "model": cfg.model,
        "messages": messages,
        "stream": False,
        "options": {
            "temperature": temperature if temperature is not None else cfg.temperature,
            "num_predict": max_tokens,
        },
    }
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = request.Request(
        f"{cfg.base_url}/api/chat",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with request.urlopen(req, timeout=cfg.timeout_seconds) as resp:
            data = json.loads(resp.read())
        content = data.get("message", {}).get("content", "").strip()
        return content or None
    except Exception as exc:
        print(f"[ollama] chat error: {exc}", file=sys.stderr)
        return None


# ---------------------------------------------------------------------------
# High-level helpers
# ---------------------------------------------------------------------------

SYSTEM_PERSONA = (
    "Ты — Obsidian-агент. Отвечай коротко, по-русски, без markdown-разметки. "
    "Максимум 2-3 предложения."
)


def llm_classify_message(cfg: LLMConfig, text: str) -> str | None:
    """Classify a message into signal/personal/noise/tracking. Returns bucket or None."""
    if not cfg.smart_classify:
        return None
    prompt = (
        "Классифицируй сообщение пользователя в одну из категорий. "
        "Ответь ОДНИМ словом без пояснений:\n"
        "- signal — полезная идея, задача, проект, заметка, гипотеза\n"
        "- personal — личные переживания, эмоции, дневник\n"
        "- tracking — тренировка, еда, вес, навык (gym, food, skill, weight, sleep)\n"
        "- noise — приветствие, тест, мусор, короткая реплика без содержания\n\n"
        f"Сообщение: \"{text[:800]}\""
    )
    result = ollama_chat(cfg, [
        {"role": "system", "content": "Ты — классификатор сообщений. Отвечай одним словом."},
        {"role": "user", "content": prompt},
    ], temperature=0.1, max_tokens=16)
    if result is None:
        return None
    token = result.strip().casefold().rstrip(".")
    if token in {"signal", "personal", "noise", "tracking"}:
        return token
    return None


def llm_infer_note_kind(cfg: LLMConfig, text: str) -> tuple[str, str] | None:
    """Determine if a signal is an idea, thought, or post. Returns (kind, confidence) or None."""
    if not cfg.smart_classify:
        return None
    prompt = (
        "Определи тип заметки. Ответь ОДНИМ словом без пояснений:\n"
        "- idea — конкретная идея, проект, продукт, фича, гипотеза\n"
        "- thought — наблюдение, размышление, инсайт, осознание\n"
        "- post — контент для публикации, пост, тред, черновик статьи\n\n"
        f"Текст: \"{text[:800]}\""
    )
    result = ollama_chat(cfg, [
        {"role": "system", "content": "Ты — классификатор заметок. Отвечай одним словом."},
        {"role": "user", "content": prompt},
    ], temperature=0.1, max_tokens=16)
    if result is None:
        return None
    token = result.strip().casefold().rstrip(".")
    if token in {"idea", "thought", "post"}:
        return token, "llm-high-confidence"
    return None


def llm_smart_reply(
    cfg: LLMConfig,
    user_text: str,
    *,
    note_kind: str,
    note_path: str,
    topic_title: str | None = None,
) -> str | None:
    """Generate a short, contextual acknowledgement instead of a template string."""
    if not cfg.smart_reply:
        return None
    context_parts = [
        f"Тип: {note_kind}",
        f"Сохранено в: {note_path}",
    ]
    if topic_title:
        context_parts.append(f"Тема: {topic_title}")
    prompt = (
        "Пользователь прислал сообщение в Telegram, оно сохранено в Obsidian vault.\n"
        f"{chr(10).join(context_parts)}\n\n"
        f"Сообщение: \"{user_text[:600]}\"\n\n"
        "Ответь коротко (1-2 предложения): подтверди что принял и дай одну краткую мысль или вопрос по теме. "
        "Не повторяй текст сообщения. Не используй markdown."
    )
    return ollama_chat(cfg, [
        {"role": "system", "content": SYSTEM_PERSONA},
        {"role": "user", "content": prompt},
    ], temperature=0.5, max_tokens=150)


ROUTED_NOTE_BRACKET_LABEL: dict[str, str] = {
    "idea": "Идея",
    "thought": "Мысль",
    "post": "Пост",
}

_ROUTED_NOTE_HINTS: dict[str, tuple[str, str]] = {
    "idea": (
        "сырую идею (проект, фича, гипотеза)",
        "идею чуть яснее и полнее, без воды",
    ),
    "thought": (
        "сырую мысль или наблюдение",
        "мысль и контекст яснее, можно чуть глубже",
    ),
    "post": (
        "сырой набросок поста или публикации",
        "содержание поста структурнее: тезисы, зачем читателю, без лишней воды",
    ),
}


def _parse_routed_note_json(raw: str, bracket_label: str) -> tuple[str, str] | None:
    text = raw.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text, flags=re.IGNORECASE)
        text = re.sub(r"\s*```\s*$", "", text)
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{[\s\S]*\}", raw)
        if not match:
            return None
        try:
            data = json.loads(match.group(0))
        except json.JSONDecodeError:
            return None
    if not isinstance(data, dict):
        return None
    title = str(data.get("title", "")).strip().replace("\n", " ")
    body = str(data.get("body", "")).strip()
    if not title or not body:
        return None
    prefix = f"({bracket_label})"
    if not title.startswith(prefix):
        title = f"{prefix} " + title.lstrip()
    return title, body


def llm_format_routed_note(cfg: LLMConfig, raw_text: str, kind: str) -> tuple[str, str] | None:
    """Единый формат vault: заголовок «(Идея|Мысль|Пост) …» и развёрнутое тело."""
    bracket = ROUTED_NOTE_BRACKET_LABEL.get(kind)
    if bracket is None or not cfg.enabled or not cfg.vault_note_format:
        return None
    snippet = raw_text.strip()[:2000]
    if not snippet:
        return None
    hint = _ROUTED_NOTE_HINTS.get(kind, ("текст пользователя", "содержание яснее"))
    example_title = f"({bracket}) краткая слегка развёрнутая формулировка в стиле автора"
    prompt = (
        f"Пользователь записал {hint[0]} — возможны обрывки и разговорный стиль.\n\n"
        "Верни ТОЛЬКО один JSON-объект без текста до или после, без markdown:\n"
        f'{{"title":"{example_title}","body":"2–5 коротких абзацев: {hint[1]}"}}\n\n'
        "Требования:\n"
        f"- Поле title ОБЯЗАТЕЛЬНО начинается с «(" + bracket + ") » (скобки и пробел после метки).\n"
        "- Сохраняй лексику и тон автора, избегай канцелярита.\n"
        "- body не копирует title дословно.\n"
        "- В JSON экранируй кавычки и переносы в body как \\n.\n\n"
        f"Исходный текст:\n{snippet}"
    )
    result = ollama_chat(
        cfg,
        [
            {
                "role": "system",
                "content": (
                    "Ты умный редактор Obsidian-vault пользователя: приводишь входящие сигналы к одному "
                    "согласованному формату (заголовок с меткой в скобках + развёрнутое тело). "
                    "Отвечай только валидным JSON-объектом."
                ),
            },
            {"role": "user", "content": prompt},
        ],
        temperature=0.35,
        max_tokens=700,
    )
    if not result:
        return None
    return _parse_routed_note_json(result, bracket)


def llm_format_idea_note(cfg: LLMConfig, raw_text: str) -> tuple[str, str] | None:
    """Обратная совместимость: то же, что llm_format_routed_note(..., \"idea\")."""
    return llm_format_routed_note(cfg, raw_text, "idea")


def _parse_preflight_json(raw: str) -> dict[str, Any] | None:
    text = raw.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text, flags=re.IGNORECASE)
        text = re.sub(r"\s*```\s*$", "", text)
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{[\s\S]*\}", raw)
        if not match:
            return None
        try:
            data = json.loads(match.group(0))
        except json.JSONDecodeError:
            return None
    if not isinstance(data, dict):
        return None
    action = str(data.get("action", "")).strip().casefold()
    if action == "clarify":
        reply = str(data.get("reply", "")).strip()
        if not reply:
            return None
        return {"action": "clarify", "reply": reply}
    if action == "finalize":
        summary = str(data.get("summary", "")).strip()
        vault_text = str(data.get("vault_text", "")).strip()
        if not summary or not vault_text:
            return None
        return {"action": "finalize", "summary": summary, "vault_text": vault_text}
    return None


def llm_capture_preflight_turn(
    cfg: LLMConfig,
    *,
    bucket: str,
    turns: list[dict[str, str]],
) -> dict[str, Any] | None:
    """Уточнение перед записью в vault: clarify (ответ пользователю) или finalize (саммари + текст для записи)."""
    if not cfg.enabled or not cfg.smart_reply:
        return None
    bucket_ru = {"signal": "сигнал (идея/проект/задача в knowledge)", "personal": "личная заметка"}.get(
        bucket, bucket
    )
    lines: list[str] = []
    for t in turns[-14:]:
        role = t.get("role", "")
        content = (t.get("content") or "").strip()
        if not content:
            continue
        prefix = "Пользователь" if role == "user" else "Ты (бот)"
        lines.append(f"{prefix}: {content}")
    transcript = "\n".join(lines)
    if not transcript:
        return None
    prompt = (
        f"Ты ведёшь короткий диалог перед сохранением в Obsidian. Тип: {bucket_ru}.\n"
        "Важно: опирайся только на факты и формулировки из истории. Не выдумывай слова, не искажай русский "
        "(никаких вымышленных похожих слов вместо слов пользователя). Ключевые образы и термины из реплик "
        "пользователя сохраняй дословно или очень близко; при summarize не подменяй их другими корнями.\n\n"
        "По истории ниже реши:\n"
        "- Если не хватает деталей или логично задать ОДИН уточняющий вопрос — верни JSON:\n"
        '  {"action":"clarify","reply":"<вопрос или уточнение, 1–3 предложения, без markdown>"}\n'
        "- Если можно зафиксировать запись — верни JSON:\n"
        '  {"action":"finalize","summary":"<2–5 предложений, пересказ строго по сути реплик пользователя, без markdown>","vault_text":"<один связный текст для vault, без markdown, от лица пользователя, только из сказанного, без новых деталей>"}\n'
        "Не предлагай кнопки в тексте. Если пользователь ответил на твой прошлый вопрос — чаще finalize.\n\n"
        f"История:\n{transcript[:3500]}"
    )
    result = ollama_chat(
        cfg,
        [
            {
                "role": "system",
                "content": "Отвечай только одним JSON-объектом, без markdown и без пояснений. Пиши грамотным русским, "
                "без галлюцинаций и без слов, которых не было по смыслу в репликах пользователя.",
            },
            {"role": "user", "content": prompt},
        ],
        temperature=min(0.2, float(cfg.temperature)),
        max_tokens=600,
    )
    if not result:
        return None
    return _parse_preflight_json(result)


def llm_summarize(cfg: LLMConfig, text: str) -> str | None:
    """Generate a one-sentence summary of a note or signal."""
    if not cfg.smart_summary:
        return None
    prompt = (
        "Напиши одно предложение-резюме для этого текста. "
        "Без вводных слов, сразу суть. Максимум 30 слов.\n\n"
        f"Текст: \"{text[:1200]}\""
    )
    return ollama_chat(cfg, [
        {"role": "system", "content": "Ты — редактор заметок. Пиши кратко и точно."},
        {"role": "user", "content": prompt},
    ], temperature=0.2, max_tokens=80)


def llm_answer_vault_question(
    cfg: LLMConfig,
    question: str,
    context_notes: list[dict[str, str]],
) -> str | None:
    """Answer a question using vault note excerpts as context."""
    if not cfg.vault_questions:
        return None
    if not context_notes:
        return None
    context_block = "\n\n".join(
        f"### {note['title']}\n{note['excerpt']}"
        for note in context_notes[:5]
    )
    prompt = (
        "У тебя есть доступ к заметкам из Obsidian vault пользователя.\n"
        "Ответь на вопрос, опираясь ТОЛЬКО на эти заметки. "
        "Если информации не хватает, скажи об этом.\n\n"
        f"Заметки:\n{context_block}\n\n"
        f"Вопрос: {question}"
    )
    return ollama_chat(cfg, [
        {"role": "system", "content": SYSTEM_PERSONA},
        {"role": "user", "content": prompt},
    ], temperature=0.4, max_tokens=400)
