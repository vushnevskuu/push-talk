#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import obsidian_head_tool as head_tool

_RU_MONTH_GENITIVE = (
    "",
    "января",
    "февраля",
    "марта",
    "апреля",
    "мая",
    "июня",
    "июля",
    "августа",
    "сентября",
    "октября",
    "ноября",
    "декабря",
)


def format_ru_filename_datetime(now: datetime) -> str:
    """Дата и время для имён файлов: «17 марта 2026г., 14-05-32» (без двоеточий в времени)."""
    month = _RU_MONTH_GENITIVE[now.month]
    return f"{now.day} {month} {now.year}г., {now:%H-%M-%S}"


ACTION_VERBS = {
    "build",
    "create",
    "draft",
    "explore",
    "figure",
    "launch",
    "make",
    "plan",
    "post",
    "reason",
    "ship",
    "start",
    "write",
    "выкладывать",
    "выложить",
    "делать",
    "доделать",
    "запостить",
    "запускать",
    "исследовать",
    "написать",
    "постить",
    "продумать",
    "придумать",
    "сделать",
    "создать",
}

ROUTING_STOPWORDS = set(head_tool.STOPWORDS) | {
    "about",
    "active",
    "agent",
    "around",
    "because",
    "better",
    "could",
    "have",
    "into",
    "just",
    "maybe",
    "more",
    "should",
    "some",
    "something",
    "then",
    "there",
    "they",
    "thing",
    "think",
    "through",
    "today",
    "want",
    "will",
    "would",
    "вокруг",
    "вообще",
    "вроде",
    "грубо",
    "даже",
    "должен",
    "должна",
    "ещё",
    "значит",
    "какая",
    "какие",
    "какой",
    "какую",
    "который",
    "которые",
    "куда",
    "между",
    "может",
    "могу",
    "над",
    "нужно",
    "потом",
    "просто",
    "пусть",
    "разные",
    "свои",
    "связать",
    "связи",
    "тема",
    "темой",
    "темы",
    "тоже",
    "тут",
    "уже",
    "хочу",
    "чтобы",
} | ACTION_VERBS

IDEA_HINTS = {
    "agent",
    "app",
    "bot",
    "concept",
    "dashboard",
    "feature",
    "framework",
    "hypothesis",
    "prototype",
    "service",
    "system",
    "tool",
    "агент",
    "гипотеза",
    "дизайн",
    "идея",
    "инструмент",
    "проект",
    "сервис",
    "система",
    "фича",
}

THOUGHT_HINTS = {
    "because",
    "learned",
    "noticed",
    "realized",
    "think",
    "why",
    "заметил",
    "кажется",
    "мысль",
    "наблюдение",
    "осознал",
    "понял",
    "понимаю",
    "почему",
}

POST_HINTS = {
    "audience",
    "caption",
    "content",
    "linkedin",
    "post",
    "thread",
    "tweet",
    "выложить",
    "запостить",
    "контент",
    "линкедин",
    "пост",
    "постинг",
    "твит",
    "тред",
}

PREFIX_KIND_MAP = {
    "idea:": "idea",
    "идея:": "idea",
    "task:": "idea",
    "задача:": "idea",
    "project:": "idea",
    "проект:": "idea",
    "thought:": "thought",
    "мысль:": "thought",
    "post:": "post",
    "пост:": "post",
    "linkedin:": "post",
    "thread:": "post",
}

TOKEN_PATTERN = re.compile(r"[A-Za-zА-Яа-я0-9][A-Za-zА-Яа-я0-9_-]{2,}")
CONVERSATIONAL_TITLE_PREFIXES = (
    "вот ",
    "вот, ",
    "и да ",
    "ну ",
    "ну, ",
    "так ",
    "так, ",
    "у меня идея появилась",
    "как думаешь",
    "мне показалось",
)
TITLE_WEAK_TOKENS = {
    "идея",
    "мысль",
    "появилась",
    "появился",
    "думаешь",
    "кажется",
    "думаю",
    "будет",
    "работать",
    "думал",
    "подумал",
}


class SignalRouterError(Exception):
    pass


@dataclass
class SignalRouterConfig:
    enabled: bool = True
    idea_directory: str = "Идеи"
    thought_directory: str = "Мысли"
    post_directory: str = "посты"
    distribution_directory: str = "Inbox/Telegram/Распределение"
    themes_directory: str = "Темы"
    draft_directory: str = "Inbox/Telegram/Drafts"
    enable_drafts: bool = True
    minimum_theme_mentions: int = 2
    minimum_note_match_score: int = 40
    minimum_topic_match_score: int = 40


@dataclass
class CandidateNote:
    path: Path
    rel_path: str
    title: str
    tokens: list[str]
    semantic_tokens: list[str]
    mentions_count: int
    state: str


def load_obsidian_tool_module():
    candidate_paths = []
    env_path = os.getenv("OBSIDIAN_TOOL_PATH", "").strip()
    if env_path:
        candidate_paths.append(Path(env_path).expanduser().resolve())
    candidate_paths.append(Path.home() / ".codex" / "skills" / "obsidian-vault-manager" / "scripts" / "obsidian_tool.py")

    for path in candidate_paths:
        if not path.exists():
            continue
        spec = importlib.util.spec_from_file_location("obsidian_tool_module", path)
        if spec is None or spec.loader is None:
            continue
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        return module
    raise SignalRouterError("Could not find obsidian-vault-manager script. Set OBSIDIAN_TOOL_PATH if needed.")


def quote_yaml(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def normalize_capture_text(text: str) -> str:
    lines = [line.strip() for line in text.replace("\r\n", "\n").splitlines()]
    compact = "\n".join(line for line in lines if line)
    compact = re.sub(r"[ \t]+", " ", compact)
    return compact.strip()


def strip_signal_prefix(text: str) -> str:
    lowered = text.casefold().strip()
    for prefix in PREFIX_KIND_MAP:
        if lowered.startswith(prefix):
            return text[len(prefix) :].strip(" :-")
    return text.strip()


def safe_note_title(title: str, *, fallback: str = "Telegram Capture") -> str:
    cleaned = strip_signal_prefix(title)
    cleaned = re.sub(r"[\[\]`*_>#]", " ", cleaned)
    cleaned = re.sub(r"[\\/:*?\"<>|]+", " ", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" .-_")
    if not cleaned:
        cleaned = fallback
    if len(cleaned) > 96:
        words = cleaned.split()
        trimmed: list[str] = []
        total = 0
        for word in words:
            extra = len(word) + (1 if trimmed else 0)
            if total + extra > 96:
                break
            trimmed.append(word)
            total += extra
        cleaned = " ".join(trimmed) or cleaned[:96].rstrip()
    return cleaned


def build_note_title(text: str, kind: str, now: datetime) -> str:
    stripped = strip_signal_prefix(normalize_capture_text(text))
    if not stripped:
        return f"{kind.title()} {format_ru_filename_datetime(now)}"
    first_line = next((line.strip() for line in stripped.splitlines() if line.strip()), stripped)
    first_line = re.sub(r"^[*-]\s*", "", first_line).strip()
    sentence = re.split(r"(?<=[.!?])\s+|\n", first_line, maxsplit=1)[0].strip()
    candidate = sentence or first_line or stripped
    lowered = candidate.casefold().strip()
    while lowered.startswith(CONVERSATIONAL_TITLE_PREFIXES):
        for prefix in CONVERSATIONAL_TITLE_PREFIXES:
            if lowered.startswith(prefix):
                candidate = candidate[len(prefix) :].strip(" ,.-")
                lowered = candidate.casefold().strip()
                break
        else:
            break

    if candidate and len(candidate) <= 72 and not any((sentence or first_line or stripped).casefold().startswith(prefix) for prefix in CONVERSATIONAL_TITLE_PREFIXES):
        return safe_note_title(candidate, fallback=f"{kind.title()} {format_ru_filename_datetime(now)}")

    candidate_tokens = [token for token in meaningful_tokens(candidate) if token not in TITLE_WEAK_TOKENS][:5]
    if candidate_tokens:
        rebuilt = " ".join(candidate_tokens)
        rebuilt = rebuilt[:1].upper() + rebuilt[1:]
        return safe_note_title(rebuilt, fallback=f"{kind.title()} {format_ru_filename_datetime(now)}")

    fallback_title = {
        "idea": "Новая идея",
        "thought": "Новая мысль",
        "post": "Новый пост",
    }.get(kind, f"{kind.title()} {format_ru_filename_datetime(now)}")
    return safe_note_title(fallback_title, fallback=fallback_title)


def meaningful_tokens(text: str) -> list[str]:
    normalized = head_tool.normalize_text(text).replace("-", " ")
    seen: set[str] = set()
    tokens: list[str] = []
    for raw in TOKEN_PATTERN.findall(normalized):
        token = raw.casefold()
        if token in ROUTING_STOPWORDS:
            continue
        if len(token) <= 2:
            continue
        if token not in seen:
            seen.add(token)
            tokens.append(token)
    return tokens


def semantic_tokens(text: str, *, limit: int = 14) -> list[str]:
    return meaningful_tokens(text)[:limit]


def topic_tokens_for_signal(title: str, text: str) -> list[str]:
    title_tokens = meaningful_tokens(title)
    body_tokens = meaningful_tokens(strip_signal_prefix(text))
    merged: list[str] = []
    seen: set[str] = set()
    for token in [*title_tokens, *body_tokens]:
        if token not in seen:
            seen.add(token)
            merged.append(token)
    return merged[:6]


def has_explicit_signal_prefix(text: str) -> bool:
    lowered = normalize_capture_text(text).casefold()
    return any(lowered.startswith(prefix) for prefix in PREFIX_KIND_MAP)


def humanize_theme_title(title: str, tokens: list[str]) -> str:
    cleaned_title = safe_note_title(title, fallback="Тема")
    words = cleaned_title.split()
    if words:
        trimmed_words = [
            word
            for word in words
            if head_tool.normalize_text(word) not in ACTION_VERBS
            and head_tool.normalize_text(word) not in ROUTING_STOPWORDS
        ]
        candidate = " ".join(trimmed_words[:4]).strip()
        if len(candidate) >= 8:
            return candidate
    if not tokens:
        return cleaned_title
    rendered = " ".join(tokens[:4]).strip()
    if not rendered:
        return cleaned_title
    return rendered[:1].upper() + rendered[1:]


def semantic_ngrams(text: str, *, size: int = 3) -> set[str]:
    normalized = re.sub(r"\s+", " ", head_tool.normalize_text(text)).strip()
    if len(normalized) < size:
        return set()
    return {normalized[index : index + size] for index in range(len(normalized) - size + 1)}


def infer_note_kind(text: str, *, llm_config: Any = None) -> tuple[str, str]:
    if llm_config is not None:
        try:
            import ollama_bridge
            result = ollama_bridge.llm_infer_note_kind(llm_config, text)
            if result is not None:
                return result
        except Exception:
            pass
    normalized = head_tool.normalize_text(text)
    scores = {"idea": 0, "thought": 0, "post": 0}
    for prefix, kind in PREFIX_KIND_MAP.items():
        if normalized.startswith(prefix.rstrip(":")):
            scores[kind] += 4

    for token in IDEA_HINTS:
        if token in normalized:
            scores["idea"] += 2
    for token in THOUGHT_HINTS:
        if token in normalized:
            scores["thought"] += 2
    for token in POST_HINTS:
        if token in normalized:
            scores["post"] += 2

    if re.search(r"\b(i think|i noticed|я думаю|мне кажется|я понял|заметил)\b", normalized):
        scores["thought"] += 2
    if re.search(r"\b(ship|build|prototype|app|tool|бот|сервис|продукт)\b", normalized):
        scores["idea"] += 1
    if re.search(r"\b(linkedin|thread|tweet|post|пост|линкедин|аудитори)\b", normalized):
        scores["post"] += 1

    ranked = sorted(scores.items(), key=lambda item: (item[1], item[0]), reverse=True)
    best_kind, best_score = ranked[0]
    next_score = ranked[1][1]
    if best_score <= 1:
        return "thought", "low-confidence-default"
    if best_score - next_score >= 2:
        return best_kind, "high-confidence"
    if best_kind == "post":
        return "post", "medium-confidence-post"
    if best_kind == "idea":
        return "idea", "medium-confidence-idea"
    return "thought", "medium-confidence-thought"


def relative_note_path(vault: Path, path: Path) -> str:
    return path.relative_to(vault).as_posix()


def note_link_from_path(vault: Path, path: Path) -> str:
    rel_path = relative_note_path(vault, path)
    return rel_path[:-3] if rel_path.endswith(".md") else rel_path


def render_frontmatter(data: dict[str, Any]) -> str:
    lines = ["---"]
    for key, value in data.items():
        if value is None or value == "" or value == []:
            continue
        if isinstance(value, list):
            lines.append(f"{key}:")
            for item in value:
                lines.append(f"  - {quote_yaml(str(item))}")
            continue
        lines.append(f"{key}: {quote_yaml(str(value))}")
    lines.append("---")
    return "\n".join(lines)


def merge_frontmatter(text: str, updates: dict[str, Any], obsidian_tool: Any) -> str:
    frontmatter, body = obsidian_tool.split_frontmatter(text)
    merged = dict(frontmatter)
    for key, value in updates.items():
        if value is None:
            merged.pop(key, None)
        else:
            merged[key] = value
    rendered = render_frontmatter(merged)
    clean_body = body.lstrip("\n")
    return f"{rendered}\n{clean_body}" if clean_body else rendered + "\n"


def append_block_to_section(text: str, section_name: str, block: str, obsidian_tool: Any) -> str:
    lines = text.rstrip("\n").split("\n") if text.strip() else []
    section = obsidian_tool.find_section(lines, section_name)
    block_lines = block.strip().split("\n")
    if section is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.append(f"## {section_name}")
        lines.extend(block_lines)
        return "\n".join(lines).rstrip() + "\n"

    start, end = section
    while end > start + 1 and not lines[end - 1].strip():
        end -= 1
    updated = lines[:end] + [""] + block_lines + lines[end:]
    return "\n".join(updated).rstrip() + "\n"


def capture_block(
    *,
    capture_id: str,
    now: datetime,
    source_path: Path | None,
    vault: Path,
    text: str,
    route_reason: str,
) -> str:
    lines = [
        f"### {now:%Y-%m-%d %H:%M}",
        f"- capture_id: {capture_id}",
        f"- route_reason: {route_reason}",
    ]
    if source_path is not None:
        lines.append(f"- source: [[{note_link_from_path(vault, source_path)}]]")
    lines.append("")
    lines.extend("> " + line if line else ">" for line in text.splitlines())
    return "\n".join(lines).strip()


def ensure_new_permanent_note(
    path: Path,
    *,
    title: str,
    kind: str,
    text: str,
    now: datetime,
    elaboration: str | None = None,
) -> None:
    primary_heading = {
        "idea": "Идея",
        "thought": "Мысль",
        "post": "Пост",
    }.get(kind, "Summary")
    main_block = elaboration.strip() if elaboration else text.strip()
    source_block = ""
    if elaboration:
        quoted = "\n".join("> " + line if line else ">" for line in text.splitlines())
        source_block = f"\n\n### Исходный сигнал\n\n{quoted}\n"
    frontmatter = render_frontmatter(
        {
            "title": title,
            "note_kind": kind,
            "source": "telegram",
            "created_at": now.isoformat(),
            "updated_at": now.isoformat(),
        }
    )
    body = (
        f"# {title}\n\n"
        f"## {primary_heading}\n"
        f"{main_block}{source_block}\n"
        "## Captures\n\n"
        "## Related\n"
    )
    write_text(path, frontmatter + "\n" + body)


def ensure_note_capture(
    path: Path,
    *,
    title: str,
    kind: str,
    text: str,
    capture_id: str,
    now: datetime,
    source_path: Path | None,
    vault: Path,
    route_reason: str,
    obsidian_tool: Any,
    elaboration: str | None = None,
) -> bool:
    if not path.exists():
        ensure_new_permanent_note(
            path, title=title, kind=kind, text=text, now=now, elaboration=elaboration
        )
    current = read_text(path)
    if capture_id in current:
        return False
    updated = append_block_to_section(
        current,
        "Captures",
        capture_block(
            capture_id=capture_id,
            now=now,
            source_path=source_path,
            vault=vault,
            text=text,
            route_reason=route_reason,
        ),
        obsidian_tool,
    )
    updated = merge_frontmatter(updated, {"updated_at": now.isoformat()}, obsidian_tool)
    write_text(path, updated)
    return True


def score_text_similarity(left_title: str, left_tokens: list[str], right_title: str, right_tokens: list[str]) -> int:
    left_norm = head_tool.normalize_text(left_title)
    right_norm = head_tool.normalize_text(right_title)
    if left_norm == right_norm:
        return 100
    score = 0
    if left_norm and right_norm and (left_norm in right_norm or right_norm in left_norm):
        score += 45
    shared = len(set(token_signature(token) for token in left_tokens) & set(token_signature(token) for token in right_tokens))
    score += shared * 18
    if left_tokens and right_tokens and token_signature(left_tokens[0]) == token_signature(right_tokens[0]):
        score += 8
    if shared >= 2:
        score += 6
    left_ngrams = semantic_ngrams(left_title + " " + " ".join(left_tokens[:8]))
    right_ngrams = semantic_ngrams(right_title + " " + " ".join(right_tokens[:8]))
    if left_ngrams and right_ngrams:
        overlap = len(left_ngrams & right_ngrams) / max(1, len(left_ngrams | right_ngrams))
        score += int(overlap * 28)
    return score


def token_signature(token: str) -> str:
    normalized = head_tool.normalize_text(token)
    if len(normalized) <= 4:
        return normalized
    for suffix in ("иями", "ями", "ами", "ого", "ему", "ому", "ыми", "ими", "ыми", "его", "ими", "ами"):
        if normalized.endswith(suffix) and len(normalized) - len(suffix) >= 4:
            return normalized[: -len(suffix)]
    for suffix in ("ов", "ев", "ам", "ям", "ах", "ях", "ом", "ем", "ой", "ей", "ую", "юю", "ых", "их", "ый", "ий", "ая", "яя", "ое", "ее", "ые", "ие", "ам", "ям", "у", "ю", "а", "я", "ы", "и", "е", "о", "s"):
        if normalized.endswith(suffix) and len(normalized) - len(suffix) >= 4:
            return normalized[: -len(suffix)]
    for suffix in ("ing", "ers", "ies", "ied", "ed", "es"):
        if normalized.endswith(suffix) and len(normalized) - len(suffix) >= 4:
            return normalized[: -len(suffix)]
    return normalized


def config_for_kind(config: SignalRouterConfig, kind: str) -> str:
    if kind == "idea":
        return config.idea_directory
    if kind == "post":
        return config.post_directory
    return config.thought_directory


def find_best_existing_note(
    index: Any,
    *,
    directory: str,
    title: str,
    tokens: list[str],
    minimum_score: int,
    obsidian_tool: Any,
) -> Any | None:
    normalized_directory = head_tool.normalize_path(directory)
    candidates = [
        note
        for note in index.notes
        if head_tool.normalize_path(note.rel_path).startswith(normalized_directory + "/")
        or head_tool.normalize_path(note.rel_path) == normalized_directory
    ]
    best_note = None
    best_score = -1
    for note in candidates:
        note_text = read_text(note.path)
        frontmatter, body = obsidian_tool.split_frontmatter(note_text)
        semantic_context = semantic_tokens(
            " ".join(
                item
                for item in [
                    note.title,
                    str(frontmatter.get("summary") or ""),
                    body[:1200],
                ]
                if item
            )
        )
        score = score_text_similarity(title, tokens, note.title, semantic_context or meaningful_tokens(note.title))
        if score > best_score:
            best_score = score
            best_note = note
    if best_note is None or best_score < minimum_score:
        return None
    return best_note


def load_candidate_notes(vault: Path, directory: str, state: str, obsidian_tool: Any) -> list[CandidateNote]:
    base = (vault / directory).resolve()
    if not base.exists():
        return []
    candidates: list[CandidateNote] = []
    for path in sorted(base.rglob("*.md")):
        if not path.is_file():
            continue
        text = read_text(path)
        frontmatter, body = obsidian_tool.split_frontmatter(text)
        title = str(frontmatter.get("title") or obsidian_tool.first_heading(body) or path.stem).strip()
        tokens = obsidian_tool.as_list(frontmatter.get("theme_tokens")) or meaningful_tokens(title)
        semantic_context = semantic_tokens(
            " ".join(
                item
                for item in [
                    title,
                    str(frontmatter.get("summary") or ""),
                    body[:1200],
                ]
                if item
            )
        )
        mentions_raw = frontmatter.get("mentions_count")
        try:
            mentions_count = int(str(mentions_raw).strip())
        except (TypeError, ValueError):
            mentions_count = 0
        candidates.append(
            CandidateNote(
                path=path,
                rel_path=relative_note_path(vault, path),
                title=title,
                tokens=tokens,
                semantic_tokens=semantic_context or tokens,
                mentions_count=mentions_count,
                state=state,
            )
        )
    return candidates


def find_best_topic_candidate(
    candidates: list[CandidateNote],
    *,
    title: str,
    tokens: list[str],
    minimum_score: int,
) -> CandidateNote | None:
    best = None
    best_score = -1
    for candidate in candidates:
        score = score_text_similarity(title, tokens, candidate.title, candidate.semantic_tokens or candidate.tokens)
        if score > best_score:
            best_score = score
            best = candidate
    if best is None or best_score < minimum_score:
        return None
    return best


def ensure_topic_note(
    path: Path,
    *,
    title: str,
    state: str,
    mentions_count: int,
    tokens: list[str],
    now: datetime,
    obsidian_tool: Any,
) -> None:
    if path.exists():
        return
    frontmatter = render_frontmatter(
        {
            "title": title,
            "routing_state": state,
            "source": "telegram-router",
            "mentions_count": str(mentions_count),
            "theme_tokens": tokens,
            "first_seen": now.isoformat(),
            "last_seen": now.isoformat(),
        }
    )
    body = (
        f"# {title}\n\n"
        "## Summary\n"
        "Сигналы по этой теме собираются здесь, пока тема не станет достаточно устойчивой.\n\n"
        "## Captures\n\n"
        "## Related\n"
    )
    write_text(path, frontmatter + "\n" + body)


def update_topic_note(
    path: Path,
    *,
    title: str,
    state: str,
    mentions_count: int,
    tokens: list[str],
    now: datetime,
    capture_id: str,
    vault: Path,
    text: str,
    source_path: Path | None,
    route_reason: str,
    obsidian_tool: Any,
) -> None:
    ensure_topic_note(path, title=title, state=state, mentions_count=mentions_count, tokens=tokens, now=now, obsidian_tool=obsidian_tool)
    current = read_text(path)
    updated = merge_frontmatter(
        current,
        {
            "title": title,
            "routing_state": state,
            "mentions_count": str(mentions_count),
            "theme_tokens": tokens,
            "last_seen": now.isoformat(),
        },
        obsidian_tool,
    )
    if capture_id not in updated:
        updated = append_block_to_section(
            updated,
            "Captures",
            capture_block(
                capture_id=capture_id,
                now=now,
                source_path=source_path,
                vault=vault,
                text=text,
                route_reason=route_reason,
            ),
            obsidian_tool,
        )
    write_text(path, updated)


def make_draft_id(now: datetime, text: str) -> str:
    digest = hashlib.sha1(normalize_capture_text(text).encode("utf-8")).hexdigest()[:8]
    return f"draft-{now:%Y%m%d-%H%M%S}-{digest}"


def build_draft_path(
    vault: Path,
    draft_id: str,
    title: str,
    now: datetime,
    config: SignalRouterConfig,
    obsidian_tool: Any,
) -> Path:
    stamp = format_ru_filename_datetime(now)
    base_title = safe_note_title(f"{stamp} {title}", fallback=f"{stamp} черновик")
    path = obsidian_tool.build_note_path(vault, base_title, None, config.draft_directory)
    if not path.exists():
        return path
    for index in range(2, 1000):
        candidate = obsidian_tool.build_note_path(
            vault, f"{base_title} {index}", None, config.draft_directory
        )
        if not candidate.exists():
            return candidate
    raise SignalRouterError(f"Could not allocate draft path for {title}")


def ensure_signal_draft(
    *,
    vault: Path,
    config: SignalRouterConfig,
    title: str,
    kind: str,
    confidence: str,
    tokens: list[str],
    text: str,
    now: datetime,
    source_path: Path | None,
    draft_reason: str,
    suggested_topic: str,
    obsidian_tool: Any,
    elaboration: str | None = None,
) -> dict[str, Any]:
    draft_id = make_draft_id(now, text)
    path = build_draft_path(vault, draft_id, title, now, config, obsidian_tool)
    topic_tokens = tokens[:8]
    frontmatter = render_frontmatter(
        {
            "title": title,
            "note_kind": "draft",
            "draft_id": draft_id,
            "draft_status": "pending",
            "proposed_kind": kind,
            "draft_reason": draft_reason,
            "source": "telegram-router",
            "created_at": now.isoformat(),
            "updated_at": now.isoformat(),
            "theme_tokens": topic_tokens,
        }
    )
    source_line = f"- source_capture: [[{note_link_from_path(vault, source_path)}]]\n" if source_path is not None else ""
    elaboration_block = ""
    if elaboration and str(elaboration).strip():
        elaboration_block = f"## Развёрнуто\n\n{str(elaboration).strip()}\n\n"
    body = (
        f"# {title}\n\n"
        "## Routing Review\n"
        f"- confidence: {confidence}\n"
        f"- proposed_kind: {kind}\n"
        f"- draft_reason: {draft_reason}\n"
        f"- suggested_topic: {suggested_topic or 'none'}\n"
        "- next_action: approve or reject this draft from Telegram\n"
        f"{source_line}\n"
        f"{elaboration_block}"
        "## Original Signal\n"
        + "\n".join("> " + line if line else ">" for line in text.splitlines())
        + "\n\n## Semantic Tokens\n"
        + f"- {', '.join(topic_tokens) or 'none'}\n"
    )
    write_text(path, frontmatter + "\n" + body)
    return {
        "draft_id": draft_id,
        "path": relative_note_path(vault, path),
        "title": title,
        "kind": kind,
        "suggested_topic": suggested_topic,
        "draft_reason": draft_reason,
    }


def should_create_draft(
    config: SignalRouterConfig,
    *,
    clean_text: str,
    confidence: str,
    existing_note: Any | None,
    best_theme: CandidateNote | None,
    best_stage: CandidateNote | None,
    force_publish: bool,
) -> tuple[bool, str]:
    if force_publish or not config.enable_drafts:
        return False, ""
    if existing_note is not None or best_theme is not None or best_stage is not None:
        return False, ""
    if has_explicit_signal_prefix(clean_text):
        return False, ""
    if confidence == "high-confidence":
        return False, ""
    return True, "semantic-review-needed"


def upsert_registry_entry(
    memory_path: Path,
    *,
    section_name: str,
    prefix: str,
    key_field: str,
    key_value: str,
    fields: dict[str, str],
) -> None:
    if not memory_path.exists():
        write_text(memory_path, head_tool.default_memory_template())
    lines = read_text(memory_path).splitlines()
    section_index = next((index for index, line in enumerate(lines) if line.strip() == f"## {section_name}"), None)
    if section_index is None:
        return

    end_index = len(lines)
    for index in range(section_index + 1, len(lines)):
        if lines[index].startswith("## "):
            end_index = index
            break

    entry_start = None
    entry_end = None
    for index in range(section_index + 1, end_index):
        if not lines[index].startswith("### "):
            continue
        next_index = end_index
        for cursor in range(index + 1, end_index):
            if lines[cursor].startswith("### "):
                next_index = cursor
                break
        candidate_block = lines[index:next_index]
        normalized_key = head_tool.normalize_text(key_value)
        for line in candidate_block:
            if line.strip().startswith(f"- {key_field}:"):
                existing_value = line.split(":", 1)[1].strip()
                if head_tool.normalize_text(existing_value) == normalized_key:
                    entry_start = index
                    entry_end = next_index
                    break
        if entry_start is not None:
            break

    if entry_start is None:
        counter = 1
        date_prefix = datetime.now(timezone.utc).strftime("%Y%m%d")
        existing_ids = {line[4:].strip() for line in lines[section_index + 1 : end_index] if line.startswith("### ")}
        while f"{prefix}-{date_prefix}-{counter:02d}" in existing_ids:
            counter += 1
        entry_id = f"{prefix}-{date_prefix}-{counter:02d}"
    else:
        entry_id = lines[entry_start][4:].strip()

    entry_lines = [f"### {entry_id}"]
    for field_name, field_value in fields.items():
        entry_lines.append(f"- {field_name}: {field_value}")
    entry_lines.append("")

    if entry_start is None:
        updated = lines[:end_index] + entry_lines + lines[end_index:]
    else:
        updated = lines[:entry_start] + entry_lines + lines[entry_end:]
    write_text(memory_path, "\n".join(updated).rstrip() + "\n")


def append_change_log(memory_path: Path, entry: str) -> None:
    if not memory_path.exists():
        write_text(memory_path, head_tool.default_memory_template())
    lines = read_text(memory_path).splitlines()
    section_index = next((index for index, line in enumerate(lines) if line.strip() == "## Change Log"), None)
    if section_index is None:
        return
    end_index = len(lines)
    for index in range(section_index + 1, len(lines)):
        if lines[index].startswith("## "):
            end_index = index
            break
    bullet = f"- {entry}"
    if bullet in lines[section_index:end_index]:
        return
    insert_at = end_index
    updated = lines[:insert_at] + [bullet] + lines[insert_at:]
    write_text(memory_path, "\n".join(updated).rstrip() + "\n")


def route_signal(
    *,
    vault: Path,
    text: str,
    source_path: Path | None = None,
    memory_path: Path | None = None,
    timezone_name: str = "UTC",
    routing_settings: dict[str, Any] | None = None,
    force_publish: bool = False,
    llm_config: Any = None,
) -> dict[str, Any]:
    vault = vault.expanduser().resolve()
    config = SignalRouterConfig(**(routing_settings or {}))
    if not config.enabled:
        return {"routed": False, "reason": "disabled", "message": "Signal routing disabled."}

    obsidian_tool = load_obsidian_tool_module()
    now = datetime.now(ZoneInfo(timezone_name))
    clean_text = normalize_capture_text(text)
    if not clean_text:
        return {"routed": False, "reason": "empty", "message": "Nothing to route."}

    kind, confidence = infer_note_kind(clean_text, llm_config=llm_config)
    title = build_note_title(clean_text, kind, now)
    tokens = topic_tokens_for_signal(title, clean_text)
    index = obsidian_tool.build_index(vault)
    target_directory = config_for_kind(config, kind)
    existing_note = find_best_existing_note(
        index,
        directory=target_directory,
        title=title,
        tokens=tokens,
        minimum_score=config.minimum_note_match_score,
        obsidian_tool=obsidian_tool,
    )
    theme_candidates = load_candidate_notes(vault, config.themes_directory, "theme", obsidian_tool)
    stage_candidates = load_candidate_notes(vault, config.distribution_directory, "staging", obsidian_tool)
    best_theme = find_best_topic_candidate(
        theme_candidates,
        title=title,
        tokens=tokens,
        minimum_score=config.minimum_topic_match_score,
    )
    best_stage = find_best_topic_candidate(
        stage_candidates,
        title=title,
        tokens=tokens,
        minimum_score=config.minimum_topic_match_score,
    )
    should_draft, draft_reason = should_create_draft(
        config,
        clean_text=clean_text,
        confidence=confidence,
        existing_note=existing_note,
        best_theme=best_theme,
        best_stage=best_stage,
        force_publish=force_publish,
    )
    note_elaboration: str | None = None
    if (
        kind in ("idea", "thought", "post")
        and llm_config is not None
        and (should_draft or existing_note is None)
    ):
        try:
            import ollama_bridge

            pair = ollama_bridge.llm_format_routed_note(llm_config, clean_text, kind)
            if pair:
                llm_title, llm_body = pair
                title = safe_note_title(llm_title, fallback=title)
                note_elaboration = llm_body
                tokens = topic_tokens_for_signal(title, clean_text)
        except Exception:
            pass
    if should_draft:
        suggested_topic = humanize_theme_title(title, tokens)
        draft_result = ensure_signal_draft(
            vault=vault,
            config=config,
            title=title,
            kind=kind,
            confidence=confidence,
            tokens=tokens,
            text=clean_text,
            now=now,
            source_path=source_path,
            draft_reason=draft_reason,
            suggested_topic=suggested_topic,
            obsidian_tool=obsidian_tool,
            elaboration=note_elaboration,
        )
        if memory_path is not None:
            append_change_log(
                memory_path,
                f"{now:%Y-%m-%d}: parked Telegram signal as draft `{draft_result['path']}` for later approval.",
            )
        return {
            "routed": True,
            "published": False,
            "draft": draft_result,
            "message": (
                f"Сигнал пока отправил в черновик `{draft_result['path']}`. "
                f"Если всё ок, пришли `/approve {draft_result['draft_id']}`. "
                f"Если не надо публиковать, пришли `/reject {draft_result['draft_id']}`."
            ),
        }
    note_created = existing_note is None
    if existing_note is None:
        note_path = obsidian_tool.build_note_path(vault, title, None, target_directory)
        note_title = title
    else:
        note_path = existing_note.path
        note_title = existing_note.title

    capture_id = f"{now:%Y%m%d%H%M%S}-{abs(hash((note_title, clean_text))) % 100000:05d}"
    ensure_note_capture(
        note_path,
        title=note_title,
        kind=kind,
        text=clean_text,
        capture_id=capture_id,
        now=now,
        source_path=source_path,
        vault=vault,
        route_reason=confidence,
        obsidian_tool=obsidian_tool,
        elaboration=note_elaboration,
    )

    if llm_config is not None and note_created and not (
        kind in ("idea", "thought", "post") and note_elaboration
    ):
        try:
            import ollama_bridge
            summary = ollama_bridge.llm_summarize(llm_config, clean_text)
            if summary:
                current = read_text(note_path)
                updated = merge_frontmatter(current, {"summary": summary}, obsidian_tool)
                if updated != current:
                    write_text(note_path, updated)
        except Exception:
            pass

    index = obsidian_tool.build_index(vault)
    note_record = obsidian_tool.resolve_note(index, relative_note_path(vault, note_path))

    topic_result: dict[str, Any] | None = None
    if best_theme is not None:
        new_mentions = max(best_theme.mentions_count + 1, 2)
        update_topic_note(
            best_theme.path,
            title=best_theme.title,
            state="theme",
            mentions_count=new_mentions,
            tokens=best_theme.tokens or tokens,
            now=now,
            capture_id=capture_id,
            vault=vault,
            text=clean_text,
            source_path=source_path,
            route_reason="matched-theme",
            obsidian_tool=obsidian_tool,
        )
        index = obsidian_tool.build_index(vault)
        theme_note = obsidian_tool.resolve_note(index, relative_note_path(vault, best_theme.path))
        obsidian_tool.update_note_with_links(note_record, [theme_note], index.stem_counts, "Related", dry_run=False)
        obsidian_tool.update_note_with_links(theme_note, [note_record], index.stem_counts, "Related", dry_run=False)
        topic_result = {
            "state": "theme",
            "promoted": False,
            "path": relative_note_path(vault, best_theme.path),
            "title": best_theme.title,
            "mentions_count": new_mentions,
        }
        if memory_path is not None:
            upsert_registry_entry(
                memory_path,
                section_name="Themes Registry",
                prefix="theme",
                key_field="theme",
                key_value=best_theme.title,
                fields={
                    "theme": best_theme.title,
                    "mentions_count": str(new_mentions),
                    "related_notes": note_record.rel_path,
                    "trend": "active",
                    "importance_estimate": "medium",
                },
            )
    else:
        best_stage = find_best_topic_candidate(
            stage_candidates,
            title=note_title,
            tokens=tokens,
            minimum_score=config.minimum_topic_match_score,
        )
        if best_stage is None:
            stage_title = humanize_theme_title(note_title, tokens)
            stage_path = obsidian_tool.build_note_path(vault, stage_title, None, config.distribution_directory)
            update_topic_note(
                stage_path,
                title=stage_title,
                state="staging",
                mentions_count=1,
                tokens=tokens,
                now=now,
                capture_id=capture_id,
                vault=vault,
                text=clean_text,
                source_path=source_path,
                route_reason="new-stage",
                obsidian_tool=obsidian_tool,
            )
            index = obsidian_tool.build_index(vault)
            stage_note = obsidian_tool.resolve_note(index, relative_note_path(vault, stage_path))
            obsidian_tool.update_note_with_links(note_record, [stage_note], index.stem_counts, "Related", dry_run=False)
            obsidian_tool.update_note_with_links(stage_note, [note_record], index.stem_counts, "Related", dry_run=False)
            topic_result = {
                "state": "staging",
                "promoted": False,
                "path": relative_note_path(vault, stage_path),
                "title": stage_title,
                "mentions_count": 1,
            }
        else:
            new_mentions = max(best_stage.mentions_count + 1, 2)
            stage_title = best_stage.title
            update_topic_note(
                best_stage.path,
                title=stage_title,
                state="staging",
                mentions_count=new_mentions,
                tokens=best_stage.tokens or tokens,
                now=now,
                capture_id=capture_id,
                vault=vault,
                text=clean_text,
                source_path=source_path,
                route_reason="matched-stage",
                obsidian_tool=obsidian_tool,
            )
            promoted = new_mentions >= config.minimum_theme_mentions
            active_path = best_stage.path
            active_title = stage_title
            state = "staging"
            if promoted:
                active_title = humanize_theme_title(stage_title, best_stage.tokens or tokens)
                theme_path = obsidian_tool.build_note_path(vault, active_title, None, config.themes_directory)
                theme_path.parent.mkdir(parents=True, exist_ok=True)
                if theme_path.resolve() != best_stage.path.resolve():
                    if theme_path.exists():
                        best_stage.path.unlink()
                    else:
                        best_stage.path.rename(theme_path)
                    active_path = theme_path
                update_topic_note(
                    active_path,
                    title=active_title,
                    state="theme",
                    mentions_count=new_mentions,
                    tokens=best_stage.tokens or tokens,
                    now=now,
                    capture_id=capture_id,
                    vault=vault,
                    text=clean_text,
                    source_path=source_path,
                    route_reason="promoted-theme",
                    obsidian_tool=obsidian_tool,
                )
                state = "theme"
                if memory_path is not None:
                    upsert_registry_entry(
                        memory_path,
                        section_name="Themes Registry",
                        prefix="theme",
                        key_field="theme",
                        key_value=active_title,
                        fields={
                            "theme": active_title,
                            "mentions_count": str(new_mentions),
                            "related_notes": note_record.rel_path,
                            "trend": "emerging",
                            "importance_estimate": "medium",
                        },
                    )
            index = obsidian_tool.build_index(vault)
            active_note = obsidian_tool.resolve_note(index, relative_note_path(vault, active_path))
            note_record = obsidian_tool.resolve_note(index, relative_note_path(vault, note_path))
            obsidian_tool.update_note_with_links(note_record, [active_note], index.stem_counts, "Related", dry_run=False)
            obsidian_tool.update_note_with_links(active_note, [note_record], index.stem_counts, "Related", dry_run=False)
            topic_result = {
                "state": state,
                "promoted": promoted,
                "path": relative_note_path(vault, active_path),
                "title": active_title,
                "mentions_count": new_mentions,
            }

    if memory_path is not None and kind == "idea":
        upsert_registry_entry(
            memory_path,
            section_name="Ideas Registry",
            prefix="idea",
            key_field="title",
            key_value=note_title,
            fields={
                "title": note_title,
                "summary": clean_text[:180],
                "source_notes": ", ".join(
                    item
                    for item in [
                        relative_note_path(vault, note_path),
                        relative_note_path(vault, source_path) if source_path is not None else "",
                    ]
                    if item
                ),
                "status": "captured",
                "first_seen": now.strftime("%Y-%m-%d"),
                "last_seen": now.strftime("%Y-%m-%d"),
                "confidence": confidence,
                "next_step": "Expand or connect it to one active project.",
                "related_ideas": topic_result["title"] if topic_result else "",
                "evidence": clean_text[:180],
                "implemented_flag": "no",
            },
        )

    if memory_path is not None:
        log_entry = f"{now:%Y-%m-%d}: routed Telegram signal into `{relative_note_path(vault, note_path)}`."
        if topic_result and topic_result["state"] == "theme":
            log_entry = (
                f"{now:%Y-%m-%d}: routed Telegram signal into `{relative_note_path(vault, note_path)}` "
                f"and updated theme `{topic_result['title']}`."
            )
        append_change_log(memory_path, log_entry)

    response = f"Принял. Сохранил в `{relative_note_path(vault, note_path)}`."
    if topic_result is not None:
        if topic_result["state"] == "staging":
            response += f" Тему пока держу в распределении: `{topic_result['title']}`."
        elif topic_result["promoted"]:
            response += f" Создал тему: `{topic_result['title']}`."
        else:
            response += f" Привязал к теме: `{topic_result['title']}`."

    return {
        "routed": True,
        "published": True,
        "note_path": relative_note_path(vault, note_path),
        "note_kind": kind,
        "note_title": note_title,
        "note_created": note_created,
        "topic": topic_result,
        "message": response,
    }


def command_route_text(args: argparse.Namespace) -> int:
    vault = Path(args.vault).expanduser().resolve()
    source_path = Path(args.source_path).expanduser().resolve() if args.source_path else None
    memory_path = Path(args.memory_path).expanduser().resolve() if args.memory_path else None
    settings = json.loads(args.routing_json) if args.routing_json else {}
    payload = route_signal(
        vault=vault,
        text=args.text,
        source_path=source_path,
        memory_path=memory_path,
        timezone_name=args.timezone,
        routing_settings=settings,
    )
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Route Telegram signal text into permanent Obsidian notes and themes.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    route_text = subparsers.add_parser("route-text", help="Route one captured signal into permanent notes and themes.")
    route_text.add_argument("vault", help="Path to the vault root")
    route_text.add_argument("--text", required=True, help="Signal text to route")
    route_text.add_argument("--source-path", help="Optional source note path for backlink context")
    route_text.add_argument("--memory-path", help="Optional Memory.md path")
    route_text.add_argument("--timezone", default="UTC", help="Timezone used for timestamps")
    route_text.add_argument("--routing-json", help="Inline JSON routing config override")
    route_text.set_defaults(func=command_route_text)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
