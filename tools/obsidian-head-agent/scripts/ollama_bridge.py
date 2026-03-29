#!/usr/bin/env python3
"""Ollama LLM bridge — thin wrapper around the local Ollama HTTP API.

All public functions gracefully return *None* when Ollama is unreachable so
callers can fall back to rule-based logic without try/except boilerplate.
"""
from __future__ import annotations

import json
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
    model: str = "qwen2.5:7b"
    temperature: float = 0.3
    timeout_seconds: int = 30
    smart_classify: bool = True
    smart_reply: bool = True
    smart_summary: bool = True
    vault_questions: bool = True


def load_llm_config(raw: dict[str, Any] | None) -> LLMConfig:
    if not raw or not isinstance(raw, dict):
        return LLMConfig()
    return LLMConfig(
        enabled=bool(raw.get("enabled", False)),
        provider=str(raw.get("provider", "ollama")),
        base_url=str(raw.get("base_url", "http://localhost:11434")).rstrip("/"),
        model=str(raw.get("model", "qwen2.5:7b")),
        temperature=float(raw.get("temperature", 0.3)),
        timeout_seconds=int(raw.get("timeout_seconds", 30)),
        smart_classify=bool(raw.get("smart_classify", True)),
        smart_reply=bool(raw.get("smart_reply", True)),
        smart_summary=bool(raw.get("smart_summary", True)),
        vault_questions=bool(raw.get("vault_questions", True)),
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
