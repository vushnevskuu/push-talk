#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from mimetypes import guess_type
from pathlib import Path
from typing import Any
from urllib import error, request
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import obsidian_graph_tool as graph_tool
import obsidian_head_tool as head_tool
import obsidian_infographic as infographic_tool
import obsidian_existing_notes_organizer as organizer_tool
import obsidian_signal_router as signal_router
import ollama_bridge

DAY_INDEX = {
    "monday": 0,
    "tuesday": 1,
    "wednesday": 2,
    "thursday": 3,
    "friday": 4,
    "saturday": 5,
    "sunday": 6,
}
DAY_LABELS_RU = {
    "monday": "пн",
    "tuesday": "вт",
    "wednesday": "ср",
    "thursday": "чт",
    "friday": "пт",
    "saturday": "сб",
    "sunday": "вс",
}

TRACKING_DIRECTORY = "Logs/Tracking"
TRACKING_FILES = {
    "skill": "skills",
    "workout": "workouts",
    "nutrition": "nutrition",
    "body": "body",
}
TRACKING_TITLES = {
    "skill": "Skill Progress",
    "workout": "Workout Log",
    "nutrition": "Nutrition Log",
    "body": "Body Log",
}
DEFAULT_XP = {
    "skill": 20,
    "workout": 25,
    "nutrition": 10,
    "body": 8,
}
WORKOUT_KEYWORDS = {
    "bench": "strength",
    "squat": "strength",
    "deadlift": "strength",
    "pullup": "strength",
    "pushup": "strength",
    "run": "conditioning",
    "cardio": "conditioning",
    "жим": "strength",
    "присед": "strength",
    "станов": "strength",
    "подтяг": "strength",
    "бег": "conditioning",
    "зал": "strength",
    "трен": "strength",
}

LOW_SIGNAL_EXACT = {
    "как дела",
    "как ты",
    "привет",
    "хай",
    "hello",
    "hi",
    "yo",
    "ок",
    "окей",
    "ага",
    "понял",
    "понятно",
    "спасибо",
    "thanks",
    "thank you",
    "тест",
    "test",
    "ping",
    "пинг",
}

LOW_SIGNAL_PREFIXES = (
    "как дела",
    "как ты",
    "привет",
    "hello",
    "hi",
    "спасибо",
    "thanks",
    "ок",
    "окей",
    "ага",
    "тест",
    "test",
)

FORCE_SIGNAL_PREFIXES = (
    "idea:",
    "idea ",
    "идея:",
    "идея ",
    "task:",
    "task ",
    "задача:",
    "задача ",
    "todo:",
    "todo ",
    "note:",
    "note ",
    "заметка:",
    "заметка ",
    "project:",
    "project ",
    "проект:",
    "проект ",
    "remember:",
    "remember ",
)

PERSONAL_PREFIXES = (
    "личное:",
    "личное ",
    "personal:",
    "personal ",
    "journal:",
    "journal ",
    "дневник:",
    "дневник ",
    "reflection:",
    "reflection ",
)

PERSONAL_KEYWORDS = {
    "чувств",
    "пережив",
    "боюсь",
    "страшно",
    "стресс",
    "reflection",
    "journal",
    "anxiety",
    "emotion",
    "эмоци",
    "отношен",
    "состояни",
}

SIGNAL_KEYWORDS = {
    "идея",
    "idea",
    "task",
    "todo",
    "задач",
    "проект",
    "project",
    "сделать",
    "надо",
    "нужно",
    "план",
    "plan",
    "hypothesis",
    "гипотез",
    "эксперимент",
    "build",
    "запомни",
    "remember",
    "исслед",
    "research",
    "мысл",
}


class BotError(Exception):
    pass


@dataclass
class ReminderRule:
    reminder_id: str
    enabled: bool
    days: set[int]
    hour: int
    minute: int
    timezone_name: str
    chat_id: int | None
    message: str


@dataclass
class BotConfig:
    bot_token: str
    vault_path: Path
    default_chat_id: int | None
    allowed_chat_ids: set[int]
    timezone_name: str
    memory_path: str
    capture_directory: str
    signal_directory: str
    personal_directory: str
    noise_directory: str
    archive_directory: str
    capture_noise: bool
    capture_bot_messages: bool
    capture_commands: bool
    acknowledgement: str
    noise_acknowledgement: str
    voice_enabled: bool
    voice_model: str
    voice_language: str | None
    vision_enabled: bool
    vision_languages: list[str]
    vision_tesseract_lang: str
    review_days_stale: int
    review_limit: int
    reminders: list[ReminderRule]
    maintenance_settings: dict[str, Any]
    routing_settings: dict[str, Any]
    local_intake_settings: dict[str, Any]
    llm_config: ollama_bridge.LLMConfig
    state_path: Path


@dataclass
class IntakeDecision:
    bucket: str
    capture: bool
    reason: str


@dataclass
class MediaAttachment:
    kind: str
    file_id: str
    file_unique_id: str
    duration_seconds: int | None
    mime_type: str | None
    file_name: str | None
    caption: str | None


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def append_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(text)


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def dump_json(path: Path, data: dict[str, Any]) -> None:
    write_text(path, json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def resolve_timezone(name: str) -> ZoneInfo:
    try:
        return ZoneInfo(name)
    except ZoneInfoNotFoundError as exc:
        raise BotError(f"Unknown timezone: {name}") from exc


def parse_days(raw_days: list[str]) -> set[int]:
    result: set[int] = set()
    for raw_day in raw_days:
        normalized = raw_day.strip().casefold()
        if normalized not in DAY_INDEX:
            raise BotError(f"Unsupported weekday in reminder: {raw_day}")
        result.add(DAY_INDEX[normalized])
    return result


def parse_time(raw_time: str) -> tuple[int, int]:
    parts = raw_time.strip().split(":")
    if len(parts) != 2:
        raise BotError(f"Reminder time must use HH:MM format: {raw_time}")
    hour = int(parts[0])
    minute = int(parts[1])
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        raise BotError(f"Reminder time out of range: {raw_time}")
    return hour, minute


def load_config(path: Path) -> BotConfig:
    raw = load_json(path)
    token = str(raw.get("bot_token", "")).strip()
    if not token:
        env_name = str(raw.get("bot_token_env", "")).strip()
        if env_name:
            token = os.getenv(env_name, "").strip()
    if not token:
        raise BotError("Telegram bot token is missing. Use bot_token or bot_token_env.")

    vault_path = Path(str(raw.get("vault_path", ""))).expanduser().resolve()
    if not vault_path.exists() or not vault_path.is_dir():
        raise BotError(f"Vault path is invalid: {vault_path}")

    default_chat_id = raw.get("default_chat_id")
    if default_chat_id is not None:
        default_chat_id = int(default_chat_id)

    allowed_chat_ids = {int(item) for item in raw.get("allowed_chat_ids", [])}
    timezone_name = str(raw.get("timezone") or "UTC")
    resolve_timezone(timezone_name)

    capture = raw.get("capture", {})
    review = raw.get("review", {})
    voice = raw.get("voice", {})
    vision = raw.get("vision", {})
    maintenance = raw.get("maintenance", {})
    routing = raw.get("routing", {})
    local_intake = raw.get("local_intake", {})
    capture_directory = str(capture.get("directory") or "Inbox/Telegram")
    signal_directory = str(capture.get("signal_directory") or f"{capture_directory}/Signal")
    personal_directory = str(capture.get("personal_directory") or f"{capture_directory}/Personal")
    noise_directory = str(capture.get("noise_directory") or f"{capture_directory}/Noise")
    archive_directory = str(capture.get("archive_directory") or f"{capture_directory}/Archive")
    reminder_rules: list[ReminderRule] = []
    for item in raw.get("reminders", []):
        hour, minute = parse_time(str(item.get("time", "09:00")))
        timezone_override = str(item.get("timezone") or timezone_name)
        resolve_timezone(timezone_override)
        reminder_rules.append(
            ReminderRule(
                reminder_id=str(item.get("id") or f"reminder-{len(reminder_rules) + 1}"),
                enabled=bool(item.get("enabled", True)),
                days=parse_days([str(day) for day in item.get("days", [])]),
                hour=hour,
                minute=minute,
                timezone_name=timezone_override,
                chat_id=int(item["chat_id"]) if item.get("chat_id") is not None else None,
                message=str(item.get("message") or "").strip(),
            )
        )

    state_path = raw.get("state_path")
    if state_path:
        resolved_state_path = Path(str(state_path)).expanduser().resolve()
    else:
        resolved_state_path = path.with_name(path.stem + ".state.json")

    return BotConfig(
        bot_token=token,
        vault_path=vault_path,
        default_chat_id=default_chat_id,
        allowed_chat_ids=allowed_chat_ids,
        timezone_name=timezone_name,
        memory_path=str(raw.get("memory_path") or "Memory.md"),
        capture_directory=capture_directory,
        signal_directory=signal_directory,
        personal_directory=personal_directory,
        noise_directory=noise_directory,
        archive_directory=archive_directory,
        capture_noise=bool(capture.get("capture_noise", False)),
        capture_bot_messages=bool(capture.get("capture_bot_messages", False)),
        capture_commands=bool(capture.get("capture_commands", False)),
        acknowledgement=str(capture.get("acknowledgement") or "Saved to Obsidian."),
        noise_acknowledgement=str(
            capture.get("noise_acknowledgement")
            or "Это не записываю в vault. Если хочешь сохранить мысль, напиши `идея:`, `задача:` или `личное:`."
        ),
        voice_enabled=bool(voice.get("enabled", True)),
        voice_model=str(voice.get("model") or "tiny"),
        voice_language=str(voice.get("language")).strip() if voice.get("language") is not None else None,
        vision_enabled=bool(vision.get("enabled", True)),
        vision_languages=[str(item) for item in vision.get("recognition_languages", ["ru-RU", "en-US"]) if str(item).strip()],
        vision_tesseract_lang=str(vision.get("tesseract_lang") or "eng"),
        review_days_stale=int(review.get("days_stale", 45)),
        review_limit=int(review.get("limit", 5)),
        reminders=reminder_rules,
        maintenance_settings=dict(maintenance) if isinstance(maintenance, dict) else {},
        routing_settings=dict(routing) if isinstance(routing, dict) else {},
        local_intake_settings=dict(local_intake) if isinstance(local_intake, dict) else {},
        llm_config=ollama_bridge.load_llm_config(raw.get("llm")),
        state_path=resolved_state_path,
    )


def load_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"last_update_id": 0, "reminders": {}, "maintenance": {"new_signal_count": 0}, "local_intake": {}}
    state = load_json(path)
    if not isinstance(state, dict):
        state = {}
    state.setdefault("last_update_id", 0)
    state.setdefault("reminders", {})
    state.setdefault("local_intake", {})
    maintenance = state.setdefault("maintenance", {})
    if not isinstance(maintenance, dict):
        maintenance = {}
        state["maintenance"] = maintenance
    maintenance.setdefault("new_signal_count", 0)
    return state


def save_state(path: Path, state: dict[str, Any]) -> None:
    dump_json(path, state)


def telegram_request(token: str, method: str, payload: dict[str, Any] | None = None) -> Any:
    url = f"https://api.telegram.org/bot{token}/{method}"
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = request.Request(url, data=data, headers=headers, method="POST" if data is not None else "GET")
    try:
        with request.urlopen(req, timeout=70) as response:
            body = response.read().decode("utf-8")
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise BotError(f"Telegram HTTP error {exc.code}: {detail}") from exc
    except error.URLError as exc:
        raise BotError(f"Telegram request failed: {exc}") from exc

    parsed = json.loads(body)
    if not parsed.get("ok"):
        raise BotError(parsed.get("description") or f"Telegram API method failed: {method}")
    return parsed.get("result")


def send_message(config: BotConfig, chat_id: int, text: str) -> Any:
    return telegram_request(
        config.bot_token,
        "sendMessage",
        {
            "chat_id": chat_id,
            "text": text[:4000],
            "disable_web_page_preview": True,
        },
    )


def encode_multipart_formdata(fields: dict[str, Any], file_field: str, file_path: Path) -> tuple[bytes, str]:
    boundary = "----ObsidianHeadAgent" + uuid.uuid4().hex
    content_type = guess_type(file_path.name)[0] or "application/octet-stream"
    body = bytearray()

    for key, value in fields.items():
        body.extend(f"--{boundary}\r\n".encode("utf-8"))
        body.extend(f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode("utf-8"))
        body.extend(str(value).encode("utf-8"))
        body.extend(b"\r\n")

    body.extend(f"--{boundary}\r\n".encode("utf-8"))
    body.extend(
        (
            f'Content-Disposition: form-data; name="{file_field}"; filename="{file_path.name}"\r\n'
            f"Content-Type: {content_type}\r\n\r\n"
        ).encode("utf-8")
    )
    body.extend(file_path.read_bytes())
    body.extend(b"\r\n")
    body.extend(f"--{boundary}--\r\n".encode("utf-8"))
    return bytes(body), boundary


def send_media(config: BotConfig, method: str, file_field: str, chat_id: int, file_path: Path, caption: str | None = None) -> Any:
    fields: dict[str, Any] = {"chat_id": chat_id}
    if caption:
        fields["caption"] = caption[:1024]
    data, boundary = encode_multipart_formdata(fields, file_field, file_path)
    headers = {"Content-Type": f"multipart/form-data; boundary={boundary}"}
    req = request.Request(
        f"https://api.telegram.org/bot{config.bot_token}/{method}",
        data=data,
        headers=headers,
        method="POST",
    )
    try:
        with request.urlopen(req, timeout=70) as response:
            body = response.read().decode("utf-8")
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise BotError(f"Telegram HTTP error {exc.code}: {detail}") from exc
    except error.URLError as exc:
        raise BotError(f"Telegram request failed: {exc}") from exc

    parsed = json.loads(body)
    if not parsed.get("ok"):
        raise BotError(parsed.get("description") or f"Telegram {method} failed")
    return parsed.get("result")


def send_document(config: BotConfig, chat_id: int, file_path: Path, caption: str | None = None) -> Any:
    return send_media(config, "sendDocument", "document", chat_id, file_path, caption=caption)


def send_photo(config: BotConfig, chat_id: int, file_path: Path, caption: str | None = None) -> Any:
    return send_media(config, "sendPhoto", "photo", chat_id, file_path, caption=caption)


def get_updates(config: BotConfig, offset: int) -> list[dict[str, Any]]:
    result = telegram_request(
        config.bot_token,
        "getUpdates",
        {
            "offset": offset,
            "timeout": 25,
            "allowed_updates": ["message"],
        },
    )
    return [item for item in result if isinstance(item, dict)]


def get_file_metadata(config: BotConfig, file_id: str) -> dict[str, Any]:
    result = telegram_request(config.bot_token, "getFile", {"file_id": file_id})
    if not isinstance(result, dict) or not result.get("file_path"):
        raise BotError("Telegram getFile returned no file_path.")
    return result


def download_telegram_file(config: BotConfig, file_id: str, destination: Path) -> Path:
    metadata = get_file_metadata(config, file_id)
    file_path = str(metadata["file_path"])
    url = f"https://api.telegram.org/file/bot{config.bot_token}/{file_path}"
    destination.parent.mkdir(parents=True, exist_ok=True)
    req = request.Request(url, method="GET")
    try:
        with request.urlopen(req, timeout=70) as response:
            data = response.read()
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise BotError(f"Telegram file download HTTP error {exc.code}: {detail}") from exc
    except error.URLError as exc:
        raise BotError(f"Telegram file download failed: {exc}") from exc
    destination.write_bytes(data)
    return destination


def extract_audio_attachment(message: dict[str, Any]) -> MediaAttachment | None:
    caption = str(message.get("caption") or "").strip() or None
    voice = message.get("voice")
    if isinstance(voice, dict) and voice.get("file_id"):
        return MediaAttachment(
            kind="voice",
            file_id=str(voice["file_id"]),
            file_unique_id=str(voice.get("file_unique_id") or voice["file_id"]),
            duration_seconds=int(voice["duration"]) if voice.get("duration") is not None else None,
            mime_type="audio/ogg",
            file_name=None,
            caption=caption,
        )

    audio = message.get("audio")
    if isinstance(audio, dict) and audio.get("file_id"):
        return MediaAttachment(
            kind="audio",
            file_id=str(audio["file_id"]),
            file_unique_id=str(audio.get("file_unique_id") or audio["file_id"]),
            duration_seconds=int(audio["duration"]) if audio.get("duration") is not None else None,
            mime_type=str(audio.get("mime_type")) if audio.get("mime_type") else None,
            file_name=str(audio.get("file_name")) if audio.get("file_name") else None,
            caption=caption,
        )

    document = message.get("document")
    if isinstance(document, dict) and document.get("file_id"):
        mime_type = str(document.get("mime_type") or "")
        if mime_type.startswith("audio/"):
            return MediaAttachment(
                kind="audio-document",
                file_id=str(document["file_id"]),
                file_unique_id=str(document.get("file_unique_id") or document["file_id"]),
                duration_seconds=None,
                mime_type=mime_type,
                file_name=str(document.get("file_name")) if document.get("file_name") else None,
                caption=caption,
            )
    return None


def extract_visual_attachment(message: dict[str, Any]) -> MediaAttachment | None:
    caption = str(message.get("caption") or "").strip() or None

    photo_sizes = message.get("photo")
    if isinstance(photo_sizes, list) and photo_sizes:
        best = photo_sizes[-1]
        if isinstance(best, dict) and best.get("file_id"):
            return MediaAttachment(
                kind="photo",
                file_id=str(best["file_id"]),
                file_unique_id=str(best.get("file_unique_id") or best["file_id"]),
                duration_seconds=None,
                mime_type="image/jpeg",
                file_name=None,
                caption=caption,
            )

    document = message.get("document")
    if isinstance(document, dict) and document.get("file_id"):
        mime_type = str(document.get("mime_type") or "")
        file_name = str(document.get("file_name")) if document.get("file_name") else None
        if mime_type.startswith("image/"):
            return MediaAttachment(
                kind="image-document",
                file_id=str(document["file_id"]),
                file_unique_id=str(document.get("file_unique_id") or document["file_id"]),
                duration_seconds=None,
                mime_type=mime_type,
                file_name=file_name,
                caption=caption,
            )
        if mime_type == "application/pdf" or (file_name and file_name.lower().endswith(".pdf")):
            return MediaAttachment(
                kind="pdf-document",
                file_id=str(document["file_id"]),
                file_unique_id=str(document.get("file_unique_id") or document["file_id"]),
                duration_seconds=None,
                mime_type="application/pdf",
                file_name=file_name,
                caption=caption,
            )
    return None


def local_whisper_transcribe(config: BotConfig, audio_path: Path) -> str:
    whisper_bin = shutil.which("whisper")
    if whisper_bin is None:
        raise BotError("Local whisper CLI is not installed.")

    with tempfile.TemporaryDirectory(prefix="telegram-voice-whisper-") as temp_dir:
        output_dir = Path(temp_dir) / "out"
        output_dir.mkdir(parents=True, exist_ok=True)
        command = [
            whisper_bin,
            str(audio_path),
            "--model",
            config.voice_model,
            "--output_dir",
            str(output_dir),
            "--output_format",
            "txt",
            "--task",
            "transcribe",
            "--verbose",
            "False",
            "--fp16",
            "False",
        ]
        if config.voice_language:
            command.extend(["--language", config.voice_language])
        completed = subprocess.run(command, capture_output=True, text=True)
        if completed.returncode != 0:
            raise BotError(
                "Whisper transcription failed: "
                + (completed.stderr.strip() or completed.stdout.strip() or "unknown error")
            )
        transcript_path = output_dir / f"{audio_path.stem}.txt"
        if not transcript_path.exists():
            raise BotError("Whisper finished without producing a transcript file.")
        return transcript_path.read_text(encoding="utf-8").strip()


def transcribe_attachment(config: BotConfig, attachment: MediaAttachment) -> str:
    if not config.voice_enabled:
        raise BotError("Voice transcription is disabled in the bot config.")

    suffix = Path(attachment.file_name or "").suffix
    if not suffix:
        suffix = ".ogg" if attachment.kind == "voice" else ".audio"
    safe_stem = re.sub(r"[^a-zA-Z0-9_-]+", "-", attachment.file_unique_id).strip("-") or "telegram-audio"

    with tempfile.TemporaryDirectory(prefix="telegram-voice-download-") as temp_dir:
        audio_path = Path(temp_dir) / f"{safe_stem}{suffix}"
        download_telegram_file(config, attachment.file_id, audio_path)
        return local_whisper_transcribe(config, audio_path)


def vision_ocr_script_path() -> Path:
    return Path(__file__).with_name("vision_ocr.swift")


def local_vision_ocr(config: BotConfig, image_path: Path) -> str:
    swift_bin = shutil.which("swift")
    if swift_bin is None:
        raise BotError("Swift is not available for macOS Vision OCR.")

    script_path = vision_ocr_script_path()
    if not script_path.exists():
        raise BotError(f"Vision OCR script is missing: {script_path}")

    command = [swift_bin, str(script_path), str(image_path)]
    for language in config.vision_languages:
        command.extend(["--lang", language])
    completed = subprocess.run(command, capture_output=True, text=True)
    if completed.returncode != 0:
        raise BotError(
            "Vision OCR failed: " + (completed.stderr.strip() or completed.stdout.strip() or "unknown error")
        )
    return completed.stdout.strip()


def local_tesseract_ocr(config: BotConfig, image_path: Path) -> str:
    tesseract_bin = shutil.which("tesseract")
    if tesseract_bin is None:
        raise BotError("tesseract is not installed.")

    with tempfile.TemporaryDirectory(prefix="telegram-image-tesseract-") as temp_dir:
        output_base = Path(temp_dir) / "ocr"
        command = [tesseract_bin, str(image_path), str(output_base), "-l", config.vision_tesseract_lang]
        completed = subprocess.run(command, capture_output=True, text=True)
        if completed.returncode != 0:
            raise BotError(
                "tesseract OCR failed: " + (completed.stderr.strip() or completed.stdout.strip() or "unknown error")
            )
        output_path = Path(str(output_base) + ".txt")
        if not output_path.exists():
            raise BotError("tesseract finished without producing text.")
        return output_path.read_text(encoding="utf-8").strip()


def extract_text_from_pdf(pdf_path: Path) -> str:
    pdftotext_bin = shutil.which("pdftotext")
    if pdftotext_bin is None:
        raise BotError("pdftotext is not installed.")
    command = [pdftotext_bin, "-layout", str(pdf_path), "-"]
    completed = subprocess.run(command, capture_output=True, text=True)
    if completed.returncode != 0:
        raise BotError(
            "pdftotext failed: " + (completed.stderr.strip() or completed.stdout.strip() or "unknown error")
        )
    return completed.stdout.strip()


def filename_suffix_for_attachment(attachment: MediaAttachment) -> str:
    suffix = Path(attachment.file_name or "").suffix
    if suffix:
        return suffix
    if attachment.kind == "photo":
        return ".jpg"
    if attachment.kind == "pdf-document":
        return ".pdf"
    guessed = mimetypes.guess_extension(attachment.mime_type or "")
    if guessed:
        return guessed
    if attachment.kind in {"image-document"}:
        return ".png"
    return ".bin"


def combine_caption_and_text(caption: str | None, extracted_text: str) -> str:
    caption_value = (caption or "").strip()
    body = extracted_text.strip()
    if caption_value and body:
        return caption_value + "\n\n" + body
    return caption_value or body


def analyze_visual_attachment(config: BotConfig, attachment: MediaAttachment) -> str:
    if not config.vision_enabled:
        raise BotError("Image/document analysis is disabled in the bot config.")

    suffix = filename_suffix_for_attachment(attachment)
    safe_stem = re.sub(r"[^a-zA-Z0-9_-]+", "-", attachment.file_unique_id).strip("-") or "telegram-visual"
    with tempfile.TemporaryDirectory(prefix="telegram-visual-download-") as temp_dir:
        local_path = Path(temp_dir) / f"{safe_stem}{suffix}"
        download_telegram_file(config, attachment.file_id, local_path)
        extracted_text = ""
        try:
            if attachment.kind == "pdf-document":
                extracted_text = extract_text_from_pdf(local_path)
            else:
                try:
                    extracted_text = local_vision_ocr(config, local_path)
                except BotError:
                    extracted_text = local_tesseract_ocr(config, local_path)
        except BotError:
            if attachment.caption:
                return attachment.caption.strip()
            raise
        combined = combine_caption_and_text(attachment.caption, extracted_text)
        return combined.strip()


def format_visual_capture_text(attachment: MediaAttachment, extracted_text: str) -> str:
    return extracted_text.strip()


def wrap_visual_response(config: BotConfig, response: str | dict[str, Any], attachment: MediaAttachment) -> str | dict[str, Any]:
    if not isinstance(response, str):
        return response
    label = "Документ" if attachment.kind == "pdf-document" else "Фото"
    if response == config.acknowledgement:
        return f"{label} разобрал. " + response
    if response == config.noise_acknowledgement:
        return f"{label} разобрал. " + response
    if response.startswith("Logged "):
        return f"{label} разобрал.\n\n" + response
    return f"{label} разобрал.\n\n" + response


def format_transcript_for_capture(transcript: str) -> str:
    return transcript.strip()


def wrap_voice_response(config: BotConfig, response: str | dict[str, Any]) -> str | dict[str, Any]:
    if not isinstance(response, str):
        return response
    if response == config.acknowledgement:
        return "Голосовое разобрал. " + response
    if response == config.noise_acknowledgement:
        return "Голосовое разобрал. " + response
    if response.startswith("Logged "):
        return "Голосовое разобрал.\n\n" + response
    return "Голосовое разобрал.\n\n" + response


def ensure_memory_file(config: BotConfig) -> Path:
    memory_path = config.vault_path / config.memory_path
    if not memory_path.exists():
        write_text(memory_path, head_tool.default_memory_template())
    return memory_path


def timestamp_now(timezone_name: str) -> datetime:
    zone = resolve_timezone(timezone_name)
    return datetime.now(zone)


def format_sender(message: dict[str, Any]) -> str:
    sender = message.get("from") or {}
    username = sender.get("username")
    first_name = sender.get("first_name")
    last_name = sender.get("last_name")
    full_name = " ".join(part for part in [first_name, last_name] if part).strip()
    if username and full_name:
        return f"{full_name} (@{username})"
    if username:
        return f"@{username}"
    if full_name:
        return full_name
    return "unknown"


def normalize_capture_text(text: str) -> str:
    return re.sub(r"\s+", " ", text.casefold()).strip()


def has_phrase(text: str, phrase: str) -> bool:
    pattern = r"(^|[\s(\[<:])" + re.escape(phrase.casefold()) + r"($|[\s)\]}>!?,.:;])"
    return re.search(pattern, text.casefold()) is not None


def capture_dir_for_bucket(config: BotConfig, bucket: str) -> str:
    if bucket == "personal":
        return config.personal_directory
    if bucket == "noise":
        return config.noise_directory
    return config.signal_directory


def capture_header(bucket: str, now: datetime) -> str:
    title = {
        "signal": "Telegram Signal",
        "personal": "Telegram Personal",
        "noise": "Telegram Noise",
    }.get(bucket, "Telegram Signal")
    return f"# {title} - {now:%Y-%m-%d}\n\n"


def capture_path(config: BotConfig, bucket: str, now: datetime) -> Path:
    return config.vault_path / capture_dir_for_bucket(config, bucket) / f"{now:%Y-%m-%d}.md"


def ensure_daily_capture_file(path: Path, now: datetime, bucket: str) -> None:
    if path.exists():
        return
    write_text(path, capture_header(bucket, now))


def word_count(text: str) -> int:
    return len(re.findall(r"[\w-]+", text, re.UNICODE))


def looks_like_symbol_noise(text: str) -> bool:
    return re.fullmatch(r"[\W_]+", text, re.UNICODE) is not None


def looks_like_personal_text(normalized: str, words: int) -> bool:
    return words >= 6 and any(keyword in normalized for keyword in PERSONAL_KEYWORDS)


def looks_like_signal_text(normalized: str, words: int, text: str) -> bool:
    if any(normalized.startswith(prefix) for prefix in PERSONAL_PREFIXES):
        return False
    if any(normalized.startswith(prefix) for prefix in FORCE_SIGNAL_PREFIXES):
        return True
    if any(keyword in normalized for keyword in SIGNAL_KEYWORDS):
        return True
    return words >= 8 or len(text.strip()) >= 48


_VAULT_QUESTION_PHRASES = [
    "что по ", "что у меня по ", "что есть по ", "расскажи про ",
    "расскажи о ", "найди ", "поищи ", "напомни про ", "напомни о ",
    "что я писал про ", "что я писал о ", "что было по ",
    "what about ", "tell me about ", "find ", "search ",
    "what do i have on ", "what did i write about ",
]


def _looks_like_vault_question(lowered: str) -> bool:
    if any(lowered.startswith(p) for p in _VAULT_QUESTION_PHRASES):
        return True
    if "?" in lowered and any(w in lowered for w in ["заметк", "vault", "идеи", "проект", "тем"]):
        return True
    return False


def answer_vault_question(config: BotConfig, question: str) -> str:
    if not ollama_bridge.ollama_available(config.llm_config):
        return "LLM недоступна. Запусти Ollama (`ollama serve`) и попробуй снова."
    tokens = signal_router.meaningful_tokens(question)
    if not tokens:
        return "Не понял вопрос. Переформулируй?"
    notes = head_tool.build_notes(config.vault_path)
    scored: list[tuple[float, Any]] = []
    for note in notes:
        note_tokens = set(
            signal_router.token_signature(t)
            for t in signal_router.meaningful_tokens(note.title)
        )
        query_tokens = set(signal_router.token_signature(t) for t in tokens)
        overlap = len(note_tokens & query_tokens)
        if overlap > 0:
            scored.append((overlap, note))
    scored.sort(key=lambda x: x[0], reverse=True)
    top = scored[:5]
    if not top:
        return "Не нашёл релевантных заметок по этому запросу."
    context_notes: list[dict[str, str]] = []
    for _, note in top:
        text = signal_router.read_text(note.path)
        _, body = signal_router.load_obsidian_tool_module().split_frontmatter(text)
        excerpt = body[:500].strip()
        context_notes.append({"title": note.title, "excerpt": excerpt})
    answer = ollama_bridge.llm_answer_vault_question(
        config.llm_config, question, context_notes
    )
    if answer:
        return answer
    titles = ", ".join(f"«{n['title']}»" for n in context_notes[:3])
    return f"Нашёл заметки по теме: {titles}. Ollama не смогла сформировать ответ."


def plain_text_query_kind(text: str) -> str | None:
    lowered = text.casefold()
    if lowered.startswith("approve ") or lowered.startswith("подтверди "):
        return "approve"
    if lowered.startswith("reject ") or lowered.startswith("отклони "):
        return "reject"
    if lowered.startswith("link ") or lowered.startswith("свяжи "):
        return "link"
    if any(has_phrase(lowered, token) for token in ["organize", "organise", "организуй", "свяжи vault", "разбери заметки", "разгреби обсидиан"]):
        return "organize"
    if any(has_phrase(lowered, token) for token in ["разбери inbox", "process inbox", "sort voice captures", "разбери voice captures", "process local intake"]):
        return "intake"
    if any(has_phrase(lowered, token) for token in ["infographic", "инфографика", "dashboard image", "report image", "visual report"]):
        return "infographic"
    if any(has_phrase(lowered, token) for token in ["квест", "quest", "what should i do", "что делать", "next step"]):
        return "quest"
    if any(has_phrase(lowered, token) for token in ["обзор", "review", "vault status", "что по vault", "что по обсидиану"]):
        return "review"
    if any(has_phrase(lowered, token) for token in ["weekly", "недельный обзор", "weekly review", "что за неделю"]):
        return "weekly"
    if any(has_phrase(lowered, token) for token in ["stats", "статистика", "статы", "метрики", "numbers"]):
        return "stats"
    if any(has_phrase(lowered, token) for token in ["memory", "память", "priority", "priorities"]):
        return "memory"
    if any(has_phrase(lowered, token) for token in ["profile", "профиль", "уровень", "level", "прокачка"]):
        return "profile"
    if any(has_phrase(lowered, token) for token in ["skills", "скиллы", "скилл", "скил", "навыки", "навык"]):
        return "skills"
    if any(has_phrase(lowered, token) for token in ["health", "здоровье", "fitness"]):
        return "health"
    if any(has_phrase(lowered, token) for token in ["sync", "синхронизируй", "проверь чат", "проверь сообщения", "check chat", "check messages"]):
        return "sync"
    if _looks_like_vault_question(lowered):
        return "ask"
    if any(has_phrase(lowered, token) for token in ["graph", "граф", "mind map", "mindmap", "карта", "связи"]):
        return "graph"
    if any(has_phrase(lowered, token) for token in ["drafts", "черновики", "pending drafts"]):
        return "drafts"
    if any(has_phrase(lowered, token) for token in ["напоминания", "reminder", "ping me on monday"]):
        return "reminders"
    return None


def classify_incoming_text(config: BotConfig, text: str) -> IntakeDecision:
    normalized = normalize_capture_text(text)
    words = word_count(text)

    if not normalized:
        return IntakeDecision(bucket="noise", capture=False, reason="empty")
    if text.startswith("/"):
        return IntakeDecision(bucket="signal", capture=config.capture_commands, reason="command")
    if any(normalized.startswith(prefix) for prefix in PERSONAL_PREFIXES):
        return IntakeDecision(bucket="personal", capture=True, reason="personal-prefix")
    if any(normalized.startswith(prefix) for prefix in FORCE_SIGNAL_PREFIXES):
        return IntakeDecision(bucket="signal", capture=True, reason="forced-signal")
    if detect_tracking_payload(text) is not None:
        return IntakeDecision(bucket="tracking", capture=False, reason="tracking")
    if plain_text_query_kind(text) is not None:
        return IntakeDecision(bucket="noise", capture=False, reason="query")
    if normalized in LOW_SIGNAL_EXACT:
        return IntakeDecision(bucket="noise", capture=config.capture_noise, reason="low-signal-exact")
    if any(normalized.startswith(prefix) for prefix in LOW_SIGNAL_PREFIXES) and words <= 5:
        return IntakeDecision(bucket="noise", capture=config.capture_noise, reason="low-signal-prefix")
    if words <= 2 or looks_like_symbol_noise(text):
        return IntakeDecision(bucket="noise", capture=config.capture_noise, reason="too-short")
    if looks_like_personal_text(normalized, words):
        return IntakeDecision(bucket="personal", capture=True, reason="personal")
    if looks_like_signal_text(normalized, words, text):
        return IntakeDecision(bucket="signal", capture=True, reason="signal")

    llm_bucket = ollama_bridge.llm_classify_message(config.llm_config, text)
    if llm_bucket == "signal":
        return IntakeDecision(bucket="signal", capture=True, reason="llm-signal")
    if llm_bucket == "personal":
        return IntakeDecision(bucket="personal", capture=True, reason="llm-personal")
    if llm_bucket == "tracking":
        return IntakeDecision(bucket="tracking", capture=False, reason="llm-tracking")

    return IntakeDecision(bucket="noise", capture=config.capture_noise, reason="default-noise")


def append_capture_entry(
    config: BotConfig,
    *,
    bucket: str,
    direction: str,
    chat_id: int,
    sender: str,
    text: str,
    extra_meta: dict[str, Any] | None = None,
    now: datetime | None = None,
) -> Path:
    current_time = now or timestamp_now(config.timezone_name)
    path = capture_path(config, bucket, current_time)
    ensure_daily_capture_file(path, current_time, bucket)
    blockquote = "\n".join(f"> {line}" if line else ">" for line in text.splitlines()) or ">"
    meta_lines = [
        f"- chat_id: {chat_id}",
        f"- sender: {sender}",
    ]
    for key, value in (extra_meta or {}).items():
        if value is None:
            continue
        meta_lines.append(f"- {key}: {sanitize_field_value(value)}")
    entry = (
        f"## {current_time:%H:%M:%S} [{direction}]\n"
        + "\n".join(meta_lines)
        + "\n\n"
        f"{blockquote}\n\n"
    )
    append_text(path, entry)
    return path


def sanitize_field_value(value: Any) -> str:
    return str(value).replace("\n", " ").strip()


def tracking_file_path(config: BotConfig, category: str, now: datetime) -> Path:
    file_stem = TRACKING_FILES[category]
    return config.vault_path / TRACKING_DIRECTORY / f"{file_stem}-{now:%Y-%m}.md"


def ensure_tracking_file(path: Path, category: str, now: datetime) -> None:
    if path.exists():
        return
    title = TRACKING_TITLES.get(category, category.title())
    write_text(path, f"# {title} - {now:%Y-%m}\n\n")


def append_tracking_entry(config: BotConfig, category: str, fields: dict[str, Any], now: datetime | None = None) -> Path:
    current_time = now or timestamp_now(config.timezone_name)
    path = tracking_file_path(config, category, current_time)
    ensure_tracking_file(path, category, current_time)
    lines = [
        f"## {current_time:%Y-%m-%d %H:%M:%S}",
        f"- timestamp: {current_time.isoformat()}",
        f"- category: {category}",
    ]
    for key, value in fields.items():
        if value is None:
            continue
        rendered = sanitize_field_value(value)
        if rendered:
            lines.append(f"- {key}: {rendered}")
    append_text(path, "\n".join(lines) + "\n\n")
    return path


def extract_first_number(pattern: str, text: str) -> float | None:
    match = re.search(pattern, text, re.IGNORECASE)
    if not match:
        return None
    return float(match.group(1).replace(",", "."))


def extract_first_int(pattern: str, text: str) -> int | None:
    value = extract_first_number(pattern, text)
    if value is None:
        return None
    return int(round(value))


def extract_xp(text: str, default: int) -> int:
    explicit = re.search(r"([+]?)(\d+)\s*xp\b", text, re.IGNORECASE)
    if explicit:
        return int(explicit.group(2))
    plus_value = re.search(r"\+(\d+)\b", text)
    if plus_value:
        return int(plus_value.group(1))
    return default


def clean_prefix(text: str, prefixes: list[str]) -> str:
    lowered = text.casefold().strip()
    for prefix in prefixes:
        if lowered.startswith(prefix):
            return text[len(prefix) :].strip(" :-")
    return text.strip()


def normalized_alpha_words(text: str) -> list[str]:
    return re.findall(r"[A-Za-zА-Яа-я]+", head_tool.normalize_text(text))


def detect_keyword_prefix(text: str, mapping: dict[str, str]) -> str | None:
    words = normalized_alpha_words(text)
    for word in words:
        for keyword in mapping:
            if word.startswith(keyword):
                return keyword
    return None


def parse_weight_reps_sets(text: str) -> tuple[float | None, int | None, int | None]:
    match = re.search(r"(\d+(?:[.,]\d+)?)\s*[xх*]\s*(\d+)(?:\s*[xх*]\s*(\d+))?", text, re.IGNORECASE)
    if not match:
        return None, None, None
    weight = float(match.group(1).replace(",", "."))
    reps = int(match.group(2))
    sets = int(match.group(3)) if match.group(3) else None
    return weight, reps, sets


def parse_skill_log(text: str) -> dict[str, Any] | None:
    lowered = text.casefold().strip()
    prefixes = ["skill:", "skill ", "скилл:", "скилл ", "навык:", "навык ", "прокачал ", "прокачка "]
    if not any(lowered.startswith(prefix) for prefix in prefixes):
        return None
    body = clean_prefix(text, prefixes)
    parts = [part.strip() for part in body.split("|", 1)]
    skill_name = re.sub(r"(\+?\d+\s*xp\b|\+\d+\b)", "", parts[0], flags=re.IGNORECASE).strip(" -:")
    note = parts[1].strip() if len(parts) == 2 else body
    if not skill_name:
        skill_name = "general"
    return {
        "category": "skill",
        "skill": skill_name,
        "xp": extract_xp(body, DEFAULT_XP["skill"]),
        "summary": note,
        "raw_text": text,
    }


def parse_workout_log(text: str) -> dict[str, Any] | None:
    lowered = text.casefold().strip()
    prefixes = ["gym:", "gym ", "workout:", "workout ", "зал:", "зал ", "тренировка:", "тренировка ", "треня:", "треня "]
    keyword_hit = detect_keyword_prefix(text, WORKOUT_KEYWORDS)
    weight, reps, sets = parse_weight_reps_sets(text)
    if not any(lowered.startswith(prefix) for prefix in prefixes) and keyword_hit is None and weight is None:
        return None
    summary = clean_prefix(text, prefixes)
    skill_name = WORKOUT_KEYWORDS.get(keyword_hit, "strength")
    return {
        "category": "workout",
        "skill": skill_name,
        "xp": extract_xp(text, DEFAULT_XP["workout"]),
        "exercise": keyword_hit or "workout",
        "weight_kg": weight,
        "reps": reps,
        "sets": sets,
        "summary": summary,
        "raw_text": text,
    }


def parse_nutrition_log(text: str) -> dict[str, Any] | None:
    lowered = text.casefold().strip()
    prefixes = ["food:", "food ", "meal:", "meal ", "съел ", "ела ", "eat ", "ate ", "еда:", "еда ", "питание:", "питание "]
    has_nutrition_signal = any(token in lowered for token in ["ккал", "kcal", "protein", "бел", "carb", "угл", "fat", "жир"])
    if not any(lowered.startswith(prefix) for prefix in prefixes) and not has_nutrition_signal:
        return None
    summary = clean_prefix(text, prefixes)
    calories = extract_first_int(r"(\d+(?:[.,]\d+)?)\s*(?:kcal|ккал|кал)\b", text)
    protein = extract_first_number(r"(\d+(?:[.,]\d+)?)\s*(?:g|гр|г)?\s*(?:protein|бел(?:ок|ка)?)\b", text)
    carbs = extract_first_number(r"(\d+(?:[.,]\d+)?)\s*(?:g|гр|г)?\s*(?:carb(?:s)?|угл(?:еводов|и)?)\b", text)
    fat = extract_first_number(r"(\d+(?:[.,]\d+)?)\s*(?:g|гр|г)?\s*(?:fat|жир(?:ов|ы)?)\b", text)
    return {
        "category": "nutrition",
        "skill": "nutrition",
        "xp": extract_xp(text, DEFAULT_XP["nutrition"]),
        "calories": calories,
        "protein_g": protein,
        "carbs_g": carbs,
        "fat_g": fat,
        "summary": summary,
        "raw_text": text,
    }


def parse_body_log(text: str) -> dict[str, Any] | None:
    lowered = text.casefold().strip()
    prefixes = ["body:", "body ", "weight:", "weight ", "вес ", "сон ", "sleep ", "steps ", "шаги "]
    has_body_signal = bool(
        re.search(r"(?<!\w)(?:weight|sleep|steps)(?!\w)", lowered)
        or re.search(r"(?<!\w)(?:вес|сон|шаги|шагов|шаг)(?!\w)", lowered)
    )
    if not any(lowered.startswith(prefix) for prefix in prefixes) and not has_body_signal:
        return None
    summary = clean_prefix(text, prefixes)
    weight = extract_first_number(r"(?:weight|вес)\s*(\d+(?:[.,]\d+)?)", text)
    if weight is None:
        weight = extract_first_number(r"(\d+(?:[.,]\d+)?)\s*(?:kg|кг)\b", text)
    sleep = extract_first_number(r"(?:sleep|сон)\s*(\d+(?:[.,]\d+)?)", text)
    steps = extract_first_int(r"(\d+)\s*(?:steps|шаг(?:ов|и)?)\b", text)
    return {
        "category": "body",
        "skill": "recovery",
        "xp": extract_xp(text, DEFAULT_XP["body"]),
        "weight_kg": weight,
        "sleep_hours": sleep,
        "steps": steps,
        "summary": summary,
        "raw_text": text,
    }


def detect_tracking_payload(text: str) -> dict[str, Any] | None:
    for parser in (parse_skill_log, parse_workout_log, parse_nutrition_log, parse_body_log):
        payload = parser(text)
        if payload is not None:
            return payload
    return None


def format_tracking_ack(payload: dict[str, Any], log_path: Path, config: BotConfig) -> str:
    category = payload["category"]
    relative_path = log_path.relative_to(config.vault_path).as_posix()
    if category == "workout":
        details: list[str] = [f"Logged workout: {payload.get('summary', 'workout')}"]
        if payload.get("weight_kg") is not None and payload.get("reps") is not None:
            load_bits = [f"{payload['weight_kg']} kg", f"{payload['reps']} reps"]
            if payload.get("sets") is not None:
                load_bits.append(f"{payload['sets']} sets")
            details.append("- " + ", ".join(load_bits))
        details.append(f"- skill xp: +{payload['xp']} to {payload['skill']}")
        details.append(f"- log: {relative_path}")
        return "\n".join(details)
    if category == "nutrition":
        details = [f"Logged nutrition: {payload.get('summary', 'meal')}"]
        nutrition_bits = []
        if payload.get("calories") is not None:
            nutrition_bits.append(f"{payload['calories']} kcal")
        if payload.get("protein_g") is not None:
            nutrition_bits.append(f"{payload['protein_g']} g protein")
        if payload.get("carbs_g") is not None:
            nutrition_bits.append(f"{payload['carbs_g']} g carbs")
        if payload.get("fat_g") is not None:
            nutrition_bits.append(f"{payload['fat_g']} g fat")
        if nutrition_bits:
            details.append("- " + ", ".join(nutrition_bits))
        details.append(f"- skill xp: +{payload['xp']} to nutrition")
        details.append(f"- log: {relative_path}")
        return "\n".join(details)
    if category == "body":
        rendered_summary = str(payload.get("summary") or "").strip()
        if re.fullmatch(r"[\d.,\s]+", rendered_summary):
            rendered_summary = str(payload.get("raw_text") or "body update")
        details = [f"Logged body data: {rendered_summary}"]
        body_bits = []
        if payload.get("weight_kg") is not None:
            body_bits.append(f"{payload['weight_kg']} kg")
        if payload.get("sleep_hours") is not None:
            body_bits.append(f"{payload['sleep_hours']} h sleep")
        if payload.get("steps") is not None:
            body_bits.append(f"{payload['steps']} steps")
        if body_bits:
            details.append("- " + ", ".join(body_bits))
        details.append(f"- skill xp: +{payload['xp']} to recovery")
        details.append(f"- log: {relative_path}")
        return "\n".join(details)
    return (
        f"Logged skill progress: {payload.get('skill', 'general')}\n"
        f"- skill xp: +{payload['xp']}\n"
        f"- note: {payload.get('summary', payload.get('raw_text', ''))}\n"
        f"- log: {relative_path}"
    )


def log_tracking_text(config: BotConfig, text: str) -> str | None:
    payload = detect_tracking_payload(text)
    if payload is None:
        return None
    path = append_tracking_entry(
        config,
        payload["category"],
        {key: value for key, value in payload.items() if key != "category"},
    )
    return format_tracking_ack(payload, path, config)


def parse_tracking_entries(config: BotConfig) -> list[dict[str, Any]]:
    tracking_root = config.vault_path / TRACKING_DIRECTORY
    if not tracking_root.exists():
        return []

    entries: list[dict[str, Any]] = []
    for path in sorted(tracking_root.glob("*.md")):
        current: dict[str, Any] | None = None
        for line in read_text(path).splitlines():
            stripped = line.strip()
            if stripped.startswith("## "):
                if current:
                    current["source_path"] = path.relative_to(config.vault_path).as_posix()
                    entries.append(current)
                current = {"heading": stripped[3:].strip()}
                continue
            if current is None or not stripped.startswith("- ") or ":" not in stripped:
                continue
            key, value = stripped[2:].split(":", 1)
            current[key.strip()] = value.strip()
        if current:
            current["source_path"] = path.relative_to(config.vault_path).as_posix()
            entries.append(current)
    return entries


def parse_entry_datetime(entry: dict[str, Any], timezone_name: str) -> datetime | None:
    raw = str(entry.get("timestamp") or entry.get("heading") or "").strip()
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw)
    except ValueError:
        try:
            parsed = datetime.strptime(raw, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            return None
        return parsed.replace(tzinfo=resolve_timezone(timezone_name))
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=resolve_timezone(timezone_name))
    return parsed


def parse_entry_number(entry: dict[str, Any], key: str) -> float | None:
    raw = entry.get(key)
    if raw in (None, ""):
        return None
    try:
        return float(str(raw).replace(",", "."))
    except ValueError:
        return None


def build_tracking_summary(config: BotConfig) -> dict[str, Any]:
    entries = parse_tracking_entries(config)
    total_xp = 0
    skill_xp: Counter[str] = Counter()
    latest_workout: dict[str, Any] | None = None
    latest_nutrition: dict[str, Any] | None = None
    latest_body: dict[str, Any] | None = None
    latest_workout_dt: datetime | None = None
    latest_nutrition_dt: datetime | None = None
    latest_body_dt: datetime | None = None
    workout_count_week = 0
    today_calories = 0.0
    today_protein = 0.0
    now_local = timestamp_now(config.timezone_name)
    current_date = now_local.date()
    current_week = now_local.isocalendar()[:2]

    for entry in entries:
        xp = int(parse_entry_number(entry, "xp") or 0)
        total_xp += xp
        skill_name = str(entry.get("skill") or "").strip()
        if skill_name:
            skill_xp[skill_name] += xp

        entry_dt = parse_entry_datetime(entry, config.timezone_name)
        category = str(entry.get("category") or "").strip()
        if category == "workout":
            if latest_workout is None or (entry_dt is not None and (latest_workout_dt is None or entry_dt > latest_workout_dt)):
                latest_workout = entry
                latest_workout_dt = entry_dt
            if entry_dt and entry_dt.astimezone(resolve_timezone(config.timezone_name)).isocalendar()[:2] == current_week:
                workout_count_week += 1
        elif category == "nutrition":
            if latest_nutrition is None or (entry_dt is not None and (latest_nutrition_dt is None or entry_dt > latest_nutrition_dt)):
                latest_nutrition = entry
                latest_nutrition_dt = entry_dt
            if entry_dt and entry_dt.astimezone(resolve_timezone(config.timezone_name)).date() == current_date:
                today_calories += parse_entry_number(entry, "calories") or 0.0
                today_protein += parse_entry_number(entry, "protein_g") or 0.0
        elif category == "body":
            if latest_body is None or (entry_dt is not None and (latest_body_dt is None or entry_dt > latest_body_dt)):
                latest_body = entry
                latest_body_dt = entry_dt

    current_level = 1 + (total_xp // 100)
    xp_into_level = total_xp % 100
    xp_to_next = 100 - xp_into_level if xp_into_level else 100
    return {
        "total_xp": total_xp,
        "level": current_level,
        "xp_into_level": xp_into_level,
        "xp_to_next": xp_to_next,
        "top_skills": skill_xp.most_common(5),
        "latest_workout": latest_workout,
        "latest_nutrition": latest_nutrition,
        "latest_body": latest_body,
        "today_calories": int(round(today_calories)),
        "today_protein": int(round(today_protein)),
        "workouts_this_week": workout_count_week,
    }


def describe_entry(entry: dict[str, Any] | None, fallback: str) -> str:
    if not entry:
        return fallback
    return str(entry.get("summary") or entry.get("raw_text") or entry.get("heading") or fallback)


def format_profile_message(config: BotConfig) -> str:
    summary = build_tracking_summary(config)
    top_skills = "; ".join(f"{short_label(skill, limit=28)} {xp} xp" for skill, xp in summary["top_skills"][:3]) or "нет"
    return render_sections(
        (
            "Профиль",
            [
                line("уровень", str(summary["level"])),
                line("xp", str(summary["total_xp"])),
                line("прогресс", f"{summary['xp_into_level']}/100"),
                line("до следующего", str(summary["xp_to_next"])),
            ],
        ),
        (
            "Фокус",
            [
                line("скиллы", top_skills),
                line("тренировки", str(summary["workouts_this_week"])),
                line("последняя тренировка", short_label(describe_entry(summary["latest_workout"], "нет"), limit=64)),
                line("питание сегодня", f"{summary['today_calories']} kcal / {summary['today_protein']} g"),
            ],
        ),
    )


def format_skills_message(config: BotConfig) -> str:
    summary = build_tracking_summary(config)
    if not summary["top_skills"]:
        return render_sections(
            (
                "Скиллы",
                [
                    line("статус", "пока нет записей"),
                    line("пример", "`skill: writing | drafted article`"),
                ],
            ),
        )
    lines = ["Skills"]
    for skill, xp in summary["top_skills"]:
        level = 1 + (xp // 100)
        lines.append(f"- {short_label(skill, limit=28)}: уровень {level}, {xp} xp")
    lines[0] = "Скиллы"
    return "\n".join(lines)


def format_health_message(config: BotConfig) -> str:
    summary = build_tracking_summary(config)
    latest_body = summary["latest_body"]
    weight = latest_body.get("weight_kg") if latest_body else None
    sleep = latest_body.get("sleep_hours") if latest_body else None
    return render_sections(
        (
            "Здоровье",
            [
                line("тренировки за неделю", str(summary["workouts_this_week"])),
                line("последняя тренировка", short_label(describe_entry(summary["latest_workout"], "нет"), limit=64)),
            ],
        ),
        (
            "Тело",
            [
                line("калории сегодня", str(summary["today_calories"])),
                line("белок сегодня", f"{summary['today_protein']} g"),
                line("вес", none_ru(str(weight) if weight is not None else "")),
                line("сон", none_ru(f"{sleep} ч" if sleep is not None else "")),
            ],
        ),
    )


def graph_excludes(config: BotConfig) -> list[str]:
    return [config.memory_path, config.capture_directory, TRACKING_DIRECTORY, infographic_tool.REPORTS_DIR]


def format_graph_message(config: BotConfig) -> str:
    summary = graph_tool.build_graph_summary(
        config.vault_path,
        limit=5,
        exclude_prefixes=graph_excludes(config),
    )
    totals = summary["totals"]
    return render_sections(
        (
            "Граф",
            [
                line("заметок", str(totals["notes"])),
                line("связей", str(totals["links"])),
                line("без связей", str(totals["orphan_notes"])),
            ],
        ),
        (
            "Фокус",
            [
                line("хабы", compact_items([item["title"] for item in summary.get("hubs", [])], limit=3)),
                line("слабые связи", compact_items([item["title"] for item in summary.get("low_link_notes", [])], limit=3)),
                line("битые ссылки", compact_items([item["target"] for item in summary.get("unresolved_links", [])], limit=3)),
            ],
        ),
    )


def connect_notes_from_argument(config: BotConfig, argument: str) -> str:
    if "|" not in argument:
        return "Use `/link Source Note | Target One, Target Two`."
    source, raw_targets = argument.split("|", 1)
    targets = [item.strip() for item in raw_targets.split(",") if item.strip()]
    if not source.strip() or not targets:
        return "Use `/link Source Note | Target One, Target Two`."
    payload = graph_tool.connect_notes_in_vault(
        config.vault_path,
        source=source.strip(),
        targets=targets,
        bidirectional=True,
    )
    if not payload["targets"]:
        return "No new links were added."
    return (
        f"Linked `{payload['source']}`\n"
        f"- targets: {', '.join(payload['targets'])}\n"
        f"- updated notes: {sum(1 for item in payload['updates'] if item.get('changed'))}"
    )


def create_infographic_response(config: BotConfig, request_text: str = "") -> dict[str, Any]:
    request_info = infographic_tool.parse_request(request_text)
    payload = infographic_tool.create_infographic(
        config.vault_path,
        config.timezone_name,
        mode=str(request_info.get("mode") or "overview"),
        skill_name=request_info.get("subject"),
    )
    type_label = payload["mode"]
    if payload.get("subject"):
        type_label = f"{type_label} / {payload['subject']}"
    return {
        "text": (
            "Generated infographic\n"
            f"- type: {type_label}\n"
            f"- file: {payload['relative_path']}\n"
            f"- updated: {payload['generated_at']}"
        ),
        "caption": f"{payload['title']} • {payload['generated_at']}",
        "photo_path": payload["png_path"],
    }


def response_log_text(response: str | dict[str, Any]) -> str:
    if isinstance(response, str):
        return response
    if response.get("text"):
        return str(response["text"])
    if response.get("caption"):
        return str(response["caption"])
    if response.get("photo_path"):
        return f"Sent image: {Path(str(response['photo_path'])).name}"
    if response.get("document_path"):
        return f"Sent document: {Path(str(response['document_path'])).name}"
    return "Sent bot response."


def deliver_response(config: BotConfig, chat_id: int, response: str | dict[str, Any]) -> str:
    if isinstance(response, str):
        send_message(config, chat_id, response)
        return response

    photo_path = response.get("photo_path")
    caption = str(response.get("caption") or response.get("text") or "").strip()
    if photo_path:
        try:
            send_photo(config, chat_id, Path(str(photo_path)), caption=caption or None)
        except BotError:
            send_document(config, chat_id, Path(str(photo_path)), caption=caption or None)
        return response_log_text(response)

    document_path = response.get("document_path")
    if document_path:
        send_document(config, chat_id, Path(str(document_path)), caption=caption or None)
        return response_log_text(response)

    text = response_log_text(response)
    send_message(config, chat_id, text)
    return text


def format_stats_message(summary: dict[str, Any]) -> str:
    totals = summary["totals"]
    return render_sections(
        (
            "Статистика",
            [
                line("заметок", str(totals["notes"])),
                line("слов", str(totals["words"])),
                line("открытых задач", str(totals["tasks_open"])),
                line("завершённых задач", str(totals["tasks_done"])),
            ],
        ),
        (
            "Структура",
            [
                line("папки", compact_items([item["folder"] for item in summary.get("top_folders", [])], limit=3, label_limit=24)),
                line("темы", compact_items([item["theme"] for item in summary.get("themes", [])], limit=3)),
                line("теги", compact_items([item["tag"] for item in summary.get("top_tags", [])], limit=3, label_limit=24)),
            ],
        ),
    )


def format_review_message(summary: dict[str, Any]) -> str:
    totals = summary["totals"]
    return render_sections(
        (
            "Обзор",
            [
                line("заметок", str(totals["notes"])),
                line("открытых задач", str(totals["tasks_open"])),
            ],
        ),
        (
            "Сейчас важно",
            [
                line("проекты", compact_items([item["title"] for item in summary.get("project_candidates", [])], limit=3)),
                line("спящие", compact_items([item["title"] for item in summary.get("dormant_candidates", [])], limit=3)),
                line("на разбор", compact_items([item["title"] for item in summary.get("cleanup_candidates", [])], limit=3)),
            ],
        ),
    )


def extract_bullets(lines: list[str]) -> list[str]:
    return [line[2:].strip() for line in lines if line.startswith("- ") and line[2:].strip()]


def read_memory_snapshot(memory_path: Path) -> dict[str, list[str]]:
    if not memory_path.exists():
        return {"priorities": [], "questions": [], "recently_completed": []}
    lines = read_text(memory_path).splitlines()
    current_subheading: str | None = None
    buckets = {
        "Current Priorities": [],
        "Questions To Resolve": [],
        "Recently Completed": [],
    }
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("### "):
            current_subheading = stripped[4:].strip()
            continue
        if current_subheading in buckets:
            buckets[current_subheading].append(stripped)
    return {
        "priorities": extract_bullets(buckets["Current Priorities"]),
        "questions": extract_bullets(buckets["Questions To Resolve"]),
        "recently_completed": extract_bullets(buckets["Recently Completed"]),
    }


def build_summary(config: BotConfig) -> dict[str, Any]:
    notes = head_tool.build_notes(config.vault_path)
    return head_tool.summarize_review(
        notes,
        days_stale=config.review_days_stale,
        limit=config.review_limit,
    )


DISPLAY_FILLER_PREFIXES = (
    "вот, ",
    "вот ",
    "и да ",
    "ну, ",
    "ну ",
    "так, ",
    "так ",
    "короче, ",
    "короче ",
    "у меня идея появилась",
    "как думаешь",
    "мне показалось",
)
DISPLAY_TOKEN_PATTERN = re.compile(r"[A-Za-zА-Яа-я0-9][A-Za-zА-Яа-я0-9_-]{2,}")
DISPLAY_WEAK_TOKENS = {
    "вот",
    "идея",
    "как",
    "меня",
    "мне",
    "мысль",
    "показалось",
    "появилась",
    "появился",
    "работать",
    "это",
    "думаешь",
    "кажется",
    "будет",
}


def rebuild_display_label(text: str) -> str:
    seen: set[str] = set()
    tokens: list[str] = []
    for raw in DISPLAY_TOKEN_PATTERN.findall(text):
        token = raw.casefold()
        if token in DISPLAY_WEAK_TOKENS:
            continue
        if token in seen:
            continue
        seen.add(token)
        tokens.append(token)
        if len(tokens) >= 5:
            break
    if tokens:
        rebuilt = " ".join(tokens)
        return rebuilt[:1].upper() + rebuilt[1:]
    lowered = text.casefold()
    if "идея" in lowered:
        return "Новая идея"
    if "пост" in lowered or "linkedin" in lowered:
        return "Новый пост"
    if "мысл" in lowered:
        return "Новая мысль"
    return "Новая заметка"


def short_label(text: str, *, limit: int = 72) -> str:
    cleaned = re.sub(r"\s+", " ", str(text or "").strip())
    original = cleaned
    lowered = cleaned.casefold()
    removed_prefix = False
    changed = True
    while cleaned and changed:
        changed = False
        for prefix in DISPLAY_FILLER_PREFIXES:
            if lowered.startswith(prefix):
                cleaned = cleaned[len(prefix) :].strip(" ,.-")
                lowered = cleaned.casefold()
                changed = True
                removed_prefix = True
    cleaned = cleaned.strip("` ")
    weak_tokens = [token.casefold() for token in DISPLAY_TOKEN_PATTERN.findall(cleaned) if token.casefold() not in DISPLAY_WEAK_TOKENS]
    if not weak_tokens:
        rebuild_source = original if not weak_tokens else (cleaned or original)
        rebuilt = rebuild_display_label(rebuild_source)
        if rebuilt:
            cleaned = rebuilt
    if cleaned:
        cleaned = cleaned[:1].upper() + cleaned[1:]
    if len(cleaned) <= limit:
        return cleaned or "без названия"
    truncated = cleaned[:limit].rsplit(" ", 1)[0].strip()
    return (truncated or cleaned[:limit]).rstrip(" ,.-") + "..."


def folder_label_from_path(rel_path: str) -> str:
    parts = Path(rel_path).parts
    return parts[0] if parts else "Vault"


def none_ru(value: str) -> str:
    return value if value else "нет"


def line(label: str, value: str) -> str:
    return f"- {label}: {value}"


def render_sections(*sections: tuple[str, list[str]]) -> str:
    blocks: list[str] = []
    for title, lines in sections:
        filtered = [item for item in lines if item]
        if filtered:
            blocks.append("\n".join([title, *filtered]))
    return "\n\n".join(blocks)


def compact_items(items: list[str], *, limit: int = 3, label_limit: int = 48) -> str:
    prepared: list[str] = []
    for item in items[:limit]:
        text = short_label(str(item), limit=label_limit)
        if text and text != "без названия":
            prepared.append(text)
    return "; ".join(prepared) or "нет"


def format_routed_signal_message(payload: dict[str, Any]) -> str:
    if payload.get("published") is False:
        draft = payload.get("draft") or {}
        lines = [
            "Черновик",
            f"- заметка: {short_label(str(draft.get('title') or 'без названия'))}",
            "- статус: ждёт подтверждения",
        ]
        suggested_topic = str(draft.get("suggested_topic") or "").strip()
        if suggested_topic:
            lines.append(f"- возможная тема: {short_label(suggested_topic)}")
        draft_id = str(draft.get("draft_id") or "").strip()
        if draft_id:
            lines.append(f"- команда: /approve {draft_id}")
        return "\n".join(lines)

    note_path = str(payload.get("note_path") or "")
    note_title = short_label(str(payload.get("note_title") or Path(note_path).stem))
    lines = [
        "Сохранено",
        f"- раздел: {folder_label_from_path(note_path)}",
        f"- заметка: {note_title}",
    ]
    topic = payload.get("topic") or {}
    topic_title = str(topic.get("title") or "").strip()
    if topic:
        if topic.get("state") == "staging":
            lines.append("- тема: в распределении")
            if topic_title:
                lines.append(f"- метка: {short_label(topic_title)}")
        elif topic.get("promoted"):
            lines.append(f"- тема: {short_label(topic_title)}")
            lines.append("- статус: создана новая тема")
        elif topic_title:
            lines.append(f"- тема: {short_label(topic_title)}")
    return "\n".join(lines)


def build_quest_payload(config: BotConfig, summary: dict[str, Any] | None = None) -> dict[str, str]:
    memory_path = ensure_memory_file(config)
    snapshot = read_memory_snapshot(memory_path)
    if snapshot["priorities"]:
        focus = short_label(snapshot["priorities"][0])
        return {
            "focus": focus,
            "step": "открой заметку и допиши одну строку: `Следующий шаг: ...`",
            "done_when": "в заметке появился один конкретный следующий шаг",
            "inline": f"продвинь приоритет «{focus}» и запиши следующий шаг",
        }
    if snapshot["questions"]:
        focus = short_label(snapshot["questions"][0])
        return {
            "focus": focus,
            "step": "запиши ответ на вопрос в 1-2 предложениях",
            "done_when": "у вопроса появилось понятное рабочее решение",
            "inline": f"закрой вопрос «{focus}» коротким решением",
        }

    review_summary = summary or build_summary(config)
    project_candidates = filter_candidate_notes(config, review_summary.get("project_candidates", []))
    dormant_candidates = filter_candidate_notes(config, review_summary.get("dormant_candidates", []))
    idea_candidates = filter_candidate_notes(config, review_summary.get("idea_candidates", []))
    cleanup_candidates = filter_candidate_notes(config, review_summary.get("cleanup_candidates", []))

    if project_candidates:
        focus = short_label(project_candidates[0]["title"])
        return {
            "focus": focus,
            "step": "добавь в заметку одну строку: `Следующий шаг: ...`",
            "done_when": "внутри заметки есть одна понятная задача",
            "inline": f"для «{focus}» запиши один конкретный следующий шаг",
        }
    if dormant_candidates:
        focus = short_label(dormant_candidates[0]["title"])
        return {
            "focus": focus,
            "step": "в начале заметки напиши: `Статус: active` или `Статус: archive`",
            "done_when": "у заметки есть статус и понятное решение по ней",
            "inline": f"реши судьбу «{focus}»: вернуть в работу или заморозить",
        }
    if idea_candidates:
        focus = short_label(idea_candidates[0]["title"])
        return {
            "focus": focus,
            "step": "допиши две строки: `Гипотеза: ...` и `Следующий шаг: ...`",
            "done_when": "идея стала чёткой гипотезой или задачей",
            "inline": f"оформи «{focus}»: сформулируй гипотезу и добавь следующий шаг",
        }
    if cleanup_candidates:
        focus = short_label(cleanup_candidates[0]["title"])
        return {
            "focus": focus,
            "step": "выбери одно из трёх: оставить, объединить или архивировать",
            "done_when": "по заметке принято одно финальное решение",
            "inline": f"разбери заметку «{focus}» и реши её судьбу",
        }
    return {
        "focus": "новая полезная мысль",
        "step": "запиши мысль и сразу добавь строку `Следующий шаг: ...`",
        "done_when": "появилась одна новая заметка без мусора",
        "inline": "зафиксируй одну полезную мысль и сразу запиши следующий шаг",
    }


def format_quest_message(config: BotConfig, summary: dict[str, Any] | None = None) -> str:
    quest = build_quest_payload(config, summary=summary)
    return (
        "Квест\n"
        f"- фокус: {quest['focus']}\n"
        f"- шаг сейчас: {quest['step']}\n"
        f"- готово, если: {quest['done_when']}"
    )


def is_system_note_path(config: BotConfig, rel_path: str) -> bool:
    normalized_rel = head_tool.normalize_path(rel_path)
    normalized_memory = head_tool.normalize_path(config.memory_path)
    if normalized_rel == normalized_memory:
        return True
    capture_roots = [
        config.capture_directory,
        config.signal_directory,
        config.personal_directory,
        config.noise_directory,
        config.archive_directory,
    ]
    for raw_root in capture_roots:
        normalized_capture_dir = head_tool.normalize_path(raw_root)
        if normalized_capture_dir and normalized_rel.startswith(normalized_capture_dir + "/"):
            return True
    for raw_root in [
        str(routing_setting(config, "themes_directory", "Темы")),
        str(routing_setting(config, "draft_directory", "Inbox/Telegram/Drafts")),
        str(local_intake_setting(config, "personal_directory", "Inbox/Personal")),
        "Inbox/_Processed",
        "Voice Captures/_Processed",
    ]:
        normalized_root = head_tool.normalize_path(raw_root)
        if normalized_root and (normalized_rel == normalized_root or normalized_rel.startswith(normalized_root + "/")):
            return True
    return False


def filter_candidate_notes(config: BotConfig, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [item for item in items if not is_system_note_path(config, str(item.get("path", "")))]


def suggest_quest(config: BotConfig, summary: dict[str, Any] | None = None) -> str:
    return build_quest_payload(config, summary=summary)["inline"]


def format_memory_message(config: BotConfig) -> str:
    memory_path = ensure_memory_file(config)
    snapshot = read_memory_snapshot(memory_path)
    return render_sections(
        (
            "Память",
            [
                line("приоритеты", compact_items(snapshot["priorities"], limit=3)),
                line("вопросы", compact_items(snapshot["questions"], limit=3)),
                line("завершено", compact_items(snapshot["recently_completed"], limit=3)),
            ],
        ),
    )


def format_reminders_message(config: BotConfig) -> str:
    if not config.reminders:
        return render_sections(("Напоминания", [line("статус", "пока нет правил")]))
    lines = ["Напоминания"]
    for reminder in config.reminders:
        days = ",".join(label for day, label in DAY_LABELS_RU.items() if DAY_INDEX[day] in reminder.days) or "нет"
        status = "вкл" if reminder.enabled else "выкл"
        lines.append(f"- {reminder.reminder_id}: {status} · {days} · {reminder.hour:02d}:{reminder.minute:02d}")
    return "\n".join(lines)


def routing_setting(config: BotConfig, key: str, default: Any) -> Any:
    value = config.routing_settings.get(key)
    return default if value is None or value == "" else value


def local_intake_setting(config: BotConfig, key: str, default: Any) -> Any:
    value = config.local_intake_settings.get(key)
    return default if value is None or value == "" else value


def local_intake_sources(config: BotConfig) -> list[str]:
    raw = local_intake_setting(config, "sources", ["Voice Captures/Inbox", "Voice Captures/Ideas", "Inbox"])
    if isinstance(raw, list):
        return [str(item) for item in raw if str(item).strip()]
    return [str(raw)]


def local_intake_excludes(config: BotConfig) -> list[str]:
    raw = local_intake_setting(
        config,
        "exclude",
        [
            "Inbox/Telegram",
            "Inbox/Personal",
            "Inbox/_Processed",
            "Voice Captures/_Processed",
        ],
    )
    if isinstance(raw, list):
        return [str(item) for item in raw if str(item).strip()]
    return [str(raw)]


def local_intake_enabled(config: BotConfig) -> bool:
    return bool(local_intake_setting(config, "enabled", True))


def local_intake_filesystem_watch(config: BotConfig) -> bool:
    return bool(local_intake_setting(config, "filesystem_watch", True))


def local_intake_normalize_frontmatter(config: BotConfig) -> bool:
    return bool(local_intake_setting(config, "normalize_markdown_frontmatter", True))


def normalize_rel(rel_path: str) -> str:
    return head_tool.normalize_path(rel_path)


def rel_matches_prefix(rel_path: str, prefix: str) -> bool:
    normalized_rel = normalize_rel(rel_path)
    normalized_prefix = normalize_rel(prefix)
    return normalized_rel == normalized_prefix or normalized_rel.startswith(normalized_prefix + "/")


def extract_note_markdown_payload(path: Path) -> dict[str, str]:
    obsidian_tool = signal_router.load_obsidian_tool_module()
    text = read_text(path)
    frontmatter, body = obsidian_tool.split_frontmatter(text)
    title = str(frontmatter.get("title") or obsidian_tool.first_heading(body) or path.stem).strip()
    body_lines = body.splitlines()
    if body_lines and body_lines[0].startswith("# "):
        body_lines = body_lines[1:]
    content = "\n".join(body_lines).strip()
    normalized = signal_router.normalize_capture_text(content or title)
    return {
        "title": title,
        "content": content,
        "text": normalized,
        "raw_text": text,
    }


def looks_like_low_signal_local_note(title: str, text: str) -> bool:
    normalized_title = head_tool.normalize_text(title)
    normalized_text = head_tool.normalize_text(text)
    words = word_count(text)
    if any(token in normalized_title for token in ["тест", "test"]) and words <= 10:
        return True
    if any(token in normalized_text for token in ["тест", "test"]) and words <= 10:
        return True
    if normalized_title.endswith(" запись") and words <= 6:
        return True
    if normalized_text in {"так вроде все работает", "это тестовый идея запиши ее", "это тестовый идея запиши её"}:
        return True
    return False


def processed_archive_path(config: BotConfig, source_path: Path) -> Path:
    rel_path = source_path.relative_to(config.vault_path)
    parts = rel_path.parts
    if not parts:
        raise BotError(f"Cannot archive source outside vault: {source_path}")
    root = Path(parts[0]) / "_Processed"
    suffix = Path(*parts[1:]) if len(parts) > 1 else Path(source_path.name)
    return unique_destination(config.vault_path / root / suffix)


def archive_local_source_note(config: BotConfig, source_path: Path, *, status: str, note_kind: str, details: dict[str, Any] | None = None) -> Path:
    obsidian_tool = signal_router.load_obsidian_tool_module()
    current = read_text(source_path)
    updates: dict[str, Any] = {
        "local_intake_status": status,
        "local_intake_kind": note_kind,
        "local_intake_processed_at": timestamp_now(config.timezone_name).isoformat(),
    }
    if details:
        for key, value in details.items():
            updates[f"local_intake_{key}"] = value
    updated = signal_router.merge_frontmatter(current, updates, obsidian_tool)
    write_text(source_path, updated)
    destination = processed_archive_path(config, source_path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    source_path.rename(destination)
    return destination


def write_local_personal_note(config: BotConfig, *, title: str, text: str, archived_source_path: Path) -> Path:
    destination_root = config.vault_path / str(local_intake_setting(config, "personal_directory", "Inbox/Personal"))
    safe_title = signal_router.safe_note_title(title, fallback="Personal Capture")
    note_path = unique_destination(destination_root / f"{safe_title}.md")
    note_body = (
        f"# {safe_title}\n\n"
        "## Personal Capture\n"
        f"{text.strip()}\n\n"
        "## Source\n"
        f"- [[{archived_source_path.relative_to(config.vault_path).with_suffix('').as_posix()}]]\n"
    )
    write_text(note_path, note_body)
    return note_path


def local_intake_reason(rel_path: str, text: str) -> IntakeDecision:
    if rel_matches_prefix(rel_path, "Voice Captures/Ideas"):
        return IntakeDecision(bucket="signal", capture=True, reason="voice-ideas")
    return IntakeDecision(bucket="", capture=False, reason="")


def brush_markdown_frontmatter_if_needed(config: BotConfig, path: Path) -> None:
    """Ensure watched .md files have title/created_at/updated_at/source for local pipeline."""
    if not local_intake_normalize_frontmatter(config):
        return
    obsidian_tool = signal_router.load_obsidian_tool_module()
    text = read_text(path)
    frontmatter, body = obsidian_tool.split_frontmatter(text)
    title_existing = str(frontmatter.get("title") or "").strip()
    derived = str(obsidian_tool.first_heading(body) or path.stem).strip()
    now = timestamp_now(config.timezone_name).isoformat()
    updates: dict[str, Any] = {}
    if not title_existing and derived:
        updates["title"] = derived
    if not str(frontmatter.get("created_at") or "").strip():
        updates["created_at"] = now
    if not str(frontmatter.get("source") or "").strip():
        updates["source"] = "local-watch"
    if not updates:
        return
    updates["updated_at"] = now
    merged = signal_router.merge_frontmatter(text, updates, obsidian_tool)
    if merged != text:
        write_text(path, merged)


def start_local_intake_watcher(config: BotConfig, wake: threading.Event) -> threading.Thread | None:
    """Background FSEvents-style watcher; requires `pip install watchdog`."""
    if not local_intake_enabled(config) or not local_intake_filesystem_watch(config):
        return None
    try:
        from watchdog.events import FileSystemEventHandler
        from watchdog.observers import Observer
    except ImportError:
        return None

    vault = config.vault_path.resolve()
    exclude_prefixes = local_intake_excludes(config)

    class _Handler(FileSystemEventHandler):
        def on_created(self, event: Any) -> None:
            self._maybe_wake(event)

        def on_modified(self, event: Any) -> None:
            self._maybe_wake(event)

        def _maybe_wake(self, event: Any) -> None:
            if getattr(event, "is_directory", False):
                return
            src = getattr(event, "src_path", "") or ""
            path = Path(str(src))
            if path.suffix.lower() != ".md":
                return
            try:
                rel = path.resolve().relative_to(vault).as_posix()
            except ValueError:
                return
            if any(rel_matches_prefix(rel, prefix) for prefix in exclude_prefixes):
                return
            wake.set()

    observer = Observer()
    handler = _Handler()
    started = False
    for raw_source in local_intake_sources(config):
        base = (vault / raw_source).resolve()
        if base.is_dir():
            observer.schedule(handler, str(base), recursive=True)
            started = True
    if not started:
        return None

    def _run() -> None:
        observer.start()
        observer.join()

    thread = threading.Thread(target=_run, name="local-intake-watch", daemon=True)
    thread.start()
    return thread


def local_intake_candidates(config: BotConfig) -> list[Path]:
    candidates: list[Path] = []
    exclude_prefixes = local_intake_excludes(config)
    for raw_source in local_intake_sources(config):
        base = (config.vault_path / raw_source).resolve()
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.md")):
            rel_path = path.relative_to(config.vault_path).as_posix()
            if any(rel_matches_prefix(rel_path, prefix) for prefix in exclude_prefixes):
                continue
            candidates.append(path)
    unique: dict[str, Path] = {}
    for path in candidates:
        unique[path.relative_to(config.vault_path).as_posix()] = path
    return [unique[key] for key in sorted(unique)]


def format_local_intake_summary(summary: dict[str, Any]) -> str:
    if not summary.get("processed", 0):
        return "Local intake: nothing new."
    lines = [
        "Local intake",
        f"- processed: {summary.get('processed', 0)}",
        f"- signal: {summary.get('signal', 0)}",
        f"- personal: {summary.get('personal', 0)}",
        f"- tracking: {summary.get('tracking', 0)}",
        f"- noise: {summary.get('noise', 0)}",
    ]
    examples = ", ".join(item["title"] for item in summary.get("items", [])[:4]) or "none"
    lines.append(f"- recent: {examples}")
    return "\n".join(lines)


def local_intake_state(state: dict[str, Any]) -> dict[str, Any]:
    intake = state.setdefault("local_intake", {})
    if not isinstance(intake, dict):
        intake = {}
        state["local_intake"] = intake
    return intake


def should_run_local_intake(config: BotConfig, state: dict[str, Any], *, force: bool = False) -> bool:
    if force:
        return True
    if not local_intake_enabled(config):
        return False
    interval_seconds = max(10, int(local_intake_setting(config, "scan_interval_seconds", 20)))
    intake = local_intake_state(state)
    last_scan_raw = str(intake.get("last_scan_at") or "").strip()
    if not last_scan_raw:
        return True
    try:
        last_scan = datetime.fromisoformat(last_scan_raw)
    except ValueError:
        return True
    return (timestamp_now(config.timezone_name) - last_scan) >= timedelta(seconds=interval_seconds)


def process_local_intake_note(config: BotConfig, path: Path) -> dict[str, Any]:
    rel_path = path.relative_to(config.vault_path).as_posix()
    payload = extract_note_markdown_payload(path)
    text = payload["text"]
    if not text:
        archived = archive_local_source_note(
            config,
            path,
            status="archived",
            note_kind="noise",
            details={"source_path": rel_path, "reason": "empty"},
        )
        return {"bucket": "noise", "title": payload["title"], "source": rel_path, "target": archived.relative_to(config.vault_path).as_posix()}
    if looks_like_low_signal_local_note(payload["title"], text):
        archived = archive_local_source_note(
            config,
            path,
            status="archived",
            note_kind="noise",
            details={"source_path": rel_path, "reason": "low-signal-local-note"},
        )
        return {"bucket": "noise", "title": payload["title"], "source": rel_path, "target": archived.relative_to(config.vault_path).as_posix()}

    forced = local_intake_reason(rel_path, text)
    decision = forced if forced.bucket else classify_incoming_text(config, text)
    routed_text = text
    if forced.reason == "voice-ideas" and not text.casefold().startswith("идея:"):
        routed_text = f"идея: {text}"

    if decision.bucket == "tracking":
        archived = archive_local_source_note(
            config,
            path,
            status="logged",
            note_kind="tracking",
            details={"source_path": rel_path, "reason": decision.reason},
        )
        log_tracking_text(config, text)
        return {"bucket": "tracking", "title": payload["title"], "source": rel_path, "target": archived.relative_to(config.vault_path).as_posix()}

    if decision.bucket == "personal":
        archived = archive_local_source_note(
            config,
            path,
            status="sorted",
            note_kind="personal",
            details={"source_path": rel_path, "reason": decision.reason},
        )
        personal_path = write_local_personal_note(
            config,
            title=payload["title"],
            text=text,
            archived_source_path=archived,
        )
        return {
            "bucket": "personal",
            "title": payload["title"],
            "source": rel_path,
            "target": personal_path.relative_to(config.vault_path).as_posix(),
        }

    if decision.bucket == "signal":
        archived = archive_local_source_note(
            config,
            path,
            status="sorted",
            note_kind="signal",
            details={"source_path": rel_path, "reason": decision.reason},
        )
        routed = signal_router.route_signal(
            vault=config.vault_path,
            text=routed_text,
            source_path=archived,
            memory_path=config.vault_path / config.memory_path,
            timezone_name=config.timezone_name,
            routing_settings=config.routing_settings,
            llm_config=config.llm_config,
        )
        target = str(routed.get("note_path") or routed.get("draft", {}).get("path") or "")
        bucket = "signal"
        if routed.get("published") is False:
            bucket = "draft"
        return {
            "bucket": bucket,
            "title": payload["title"],
            "source": rel_path,
            "target": target,
        }

    archived = archive_local_source_note(
        config,
        path,
        status="archived",
        note_kind="noise",
        details={"source_path": rel_path, "reason": decision.reason},
    )
    return {"bucket": "noise", "title": payload["title"], "source": rel_path, "target": archived.relative_to(config.vault_path).as_posix()}


def poll_local_intake(config: BotConfig, state: dict[str, Any], *, force: bool = False) -> dict[str, Any] | None:
    if not should_run_local_intake(config, state, force=force):
        return None
    intake = local_intake_state(state)
    intake["last_scan_at"] = timestamp_now(config.timezone_name).isoformat()
    items: list[dict[str, Any]] = []
    counts = {"signal": 0, "personal": 0, "tracking": 0, "noise": 0, "draft": 0}
    for path in local_intake_candidates(config):
        brush_markdown_frontmatter_if_needed(config, path)
        result = process_local_intake_note(config, path)
        items.append(result)
        bucket = str(result.get("bucket") or "noise")
        counts[bucket] = counts.get(bucket, 0) + 1
    summary = {
        "processed": len(items),
        "signal": counts.get("signal", 0) + counts.get("draft", 0),
        "personal": counts.get("personal", 0),
        "tracking": counts.get("tracking", 0),
        "noise": counts.get("noise", 0),
        "draft": counts.get("draft", 0),
        "items": items,
    }
    if summary["signal"] > 0:
        maintenance = maintenance_state(state)
        maintenance["new_signal_count"] = int(maintenance.get("new_signal_count", 0)) + int(summary["signal"])
    intake["last_summary"] = {
        "processed": summary["processed"],
        "signal": summary["signal"],
        "personal": summary["personal"],
        "tracking": summary["tracking"],
        "noise": summary["noise"],
        "draft": summary["draft"],
    }
    return summary

def draft_directory(config: BotConfig) -> Path:
    return config.vault_path / str(routing_setting(config, "draft_directory", "Inbox/Telegram/Drafts"))


def extract_section(body: str, heading: str) -> list[str]:
    lines = body.splitlines()
    inside = False
    collected: list[str] = []
    for line in lines:
        if line.startswith("## "):
            current = line[3:].strip()
            if inside:
                break
            inside = current == heading
            continue
        if inside:
            collected.append(line)
    return collected


def parse_blockquote_lines(lines: list[str]) -> str:
    extracted: list[str] = []
    for line in lines:
        if line.startswith("> "):
            extracted.append(line[2:])
        elif line == ">":
            extracted.append("")
    return "\n".join(extracted).strip()


def load_draft_records(config: BotConfig, *, statuses: set[str] | None = None) -> list[dict[str, Any]]:
    root = draft_directory(config)
    if not root.exists():
        return []
    obsidian_tool = signal_router.load_obsidian_tool_module()
    records: list[dict[str, Any]] = []
    for path in sorted(root.rglob("*.md")):
        rel_path = path.relative_to(config.vault_path).as_posix()
        if "/_" in rel_path:
            continue
        text = read_text(path)
        frontmatter, body = obsidian_tool.split_frontmatter(text)
        status = str(frontmatter.get("draft_status") or "pending").strip() or "pending"
        if statuses is not None and status not in statuses:
            continue
        title = str(frontmatter.get("title") or obsidian_tool.first_heading(body) or path.stem).strip()
        draft_id = str(frontmatter.get("draft_id") or path.stem).strip()
        records.append(
            {
                "draft_id": draft_id,
                "title": title,
                "status": status,
                "path": path,
                "rel_path": rel_path,
                "proposed_kind": str(frontmatter.get("proposed_kind") or "thought"),
                "draft_reason": str(frontmatter.get("draft_reason") or ""),
                "created_at": str(frontmatter.get("created_at") or ""),
                "source_text": parse_blockquote_lines(extract_section(body, "Original Signal")),
            }
        )
    return records


def find_draft_record(config: BotConfig, query: str) -> dict[str, Any] | None:
    normalized_query = head_tool.normalize_text(query)
    if not normalized_query:
        return None
    drafts = load_draft_records(config, statuses={"pending"})
    for draft in drafts:
        if head_tool.normalize_text(draft["draft_id"]) == normalized_query:
            return draft
    for draft in drafts:
        if normalized_query in head_tool.normalize_text(draft["title"]):
            return draft
    return None


def update_draft_note(config: BotConfig, record: dict[str, Any], updates: dict[str, Any], *, archive_folder: str | None = None) -> Path:
    obsidian_tool = signal_router.load_obsidian_tool_module()
    current_text = read_text(record["path"])
    updated = signal_router.merge_frontmatter(current_text, updates, obsidian_tool)
    write_text(record["path"], updated)
    if not archive_folder:
        return record["path"]
    destination_root = draft_directory(config) / archive_folder
    destination_root.mkdir(parents=True, exist_ok=True)
    destination = unique_destination(destination_root / record["path"].name)
    record["path"].rename(destination)
    return destination


def format_drafts_message(config: BotConfig) -> str:
    drafts = load_draft_records(config, statuses={"pending"})
    if not drafts:
        return render_sections(("Черновики", [line("статус", "пусто")]))
    lines = ["Черновики"]
    for draft in drafts[:6]:
        lines.append(f"- {draft['draft_id']}: {short_label(draft['title'])}")
    return "\n".join(lines)


def approve_draft(config: BotConfig, query: str) -> str:
    record = find_draft_record(config, query)
    if record is None:
        return "Черновик не нашёл. Посмотри `/drafts`."
    route_settings = dict(config.routing_settings)
    route_settings["enable_drafts"] = False
    result = signal_router.route_signal(
        vault=config.vault_path,
        text=str(record.get("source_text") or ""),
        source_path=record["path"],
        memory_path=config.vault_path / config.memory_path,
        timezone_name=config.timezone_name,
        routing_settings=route_settings,
        force_publish=True,
        llm_config=config.llm_config,
    )
    published_note = str(result.get("note_path") or "")
    archived_path = update_draft_note(
        config,
        record,
        {
            "draft_status": "approved",
            "approved_at": timestamp_now(config.timezone_name).isoformat(),
            "published_note": published_note,
            "updated_at": timestamp_now(config.timezone_name).isoformat(),
        },
        archive_folder="_Approved",
    )
    section = folder_label_from_path(published_note)
    title = short_label(Path(published_note).stem)
    return (
        "Черновик опубликован\n"
        f"- раздел: {section}\n"
        f"- заметка: {title}"
    )


def reject_draft(config: BotConfig, query: str) -> str:
    record = find_draft_record(config, query)
    if record is None:
        return "Черновик не нашёл. Посмотри `/drafts`."
    archived_path = update_draft_note(
        config,
        record,
        {
            "draft_status": "rejected",
            "rejected_at": timestamp_now(config.timezone_name).isoformat(),
            "updated_at": timestamp_now(config.timezone_name).isoformat(),
        },
        archive_folder="_Rejected",
    )
    return (
        "Черновик отклонён\n"
        f"- заметка: {short_label(str(record.get('title') or 'без названия'))}"
    )


def build_weekly_review_data(config: BotConfig) -> dict[str, Any]:
    now_local = timestamp_now(config.timezone_name)
    week_ago_utc = now_local.astimezone(timezone.utc) - timedelta(days=7)
    notes = head_tool.build_notes(config.vault_path)
    recent_notes = [
        note
        for note in notes
        if note.modified_at >= week_ago_utc and not is_system_note_path(config, note.rel_path)
    ]
    recent_notes.sort(key=lambda note: note.modified_at, reverse=True)

    theme_items: list[dict[str, Any]] = []
    obsidian_tool = signal_router.load_obsidian_tool_module()
    themes_root = config.vault_path / str(routing_setting(config, "themes_directory", "Темы"))
    if themes_root.exists():
        for path in sorted(themes_root.glob("*.md")):
            text = read_text(path)
            frontmatter, body = obsidian_tool.split_frontmatter(text)
            title = str(frontmatter.get("title") or obsidian_tool.first_heading(body) or path.stem).strip()
            try:
                mentions = int(str(frontmatter.get("mentions_count") or "0"))
            except ValueError:
                mentions = 0
            theme_items.append({"title": title, "mentions_count": mentions})
    theme_items.sort(key=lambda item: (item["mentions_count"], item["title"]), reverse=True)

    return {
        "notes_touched": len(recent_notes),
        "recent_notes": [note.title for note in recent_notes[:5]],
        "themes": theme_items[:5],
        "pending_drafts": load_draft_records(config, statuses={"pending"})[:5],
        "tracking": build_tracking_summary(config),
        "quest": suggest_quest(config),
    }


def format_weekly_review_message(config: BotConfig) -> str:
    summary = build_weekly_review_data(config)
    recent = compact_items(summary["recent_notes"], limit=4)
    themes = "; ".join(f"{short_label(item['title'], limit=36)} ({item['mentions_count']})" for item in summary["themes"]) or "нет"
    drafts = compact_items([item["title"] for item in summary["pending_drafts"]], limit=4)
    tracking = summary["tracking"]
    return render_sections(
        (
            "Неделя",
            [
                line("активность", f"{summary['notes_touched']} заметок"),
                line("тренировки", str(tracking.get("workouts_this_week", 0))),
            ],
        ),
        (
            "Рост",
            [
                line("свежее", recent),
                line("темы", themes),
                line("черновики", drafts),
            ],
        ),
        (
            "Фокус",
            [
                line("квест", summary["quest"]),
            ],
        ),
    )


def maintenance_state(state: dict[str, Any]) -> dict[str, Any]:
    maintenance = state.setdefault("maintenance", {})
    if not isinstance(maintenance, dict):
        maintenance = {}
        state["maintenance"] = maintenance
    maintenance.setdefault("new_signal_count", 0)
    return maintenance


def count_organizer_changes(summary: dict[str, Any]) -> int:
    related = sum(1 for item in summary.get("related_links", []) if item.get("source_changed") or item.get("target_changed"))
    themes = sum(1 for item in summary.get("themes", []) if item.get("theme_changed") or int(item.get("backlinks_changed", 0)) > 0)
    normalized = len(summary.get("normalized_notes", []))
    staged = len(summary.get("staged_notes", []))
    return related + themes + normalized + staged


def format_organizer_summary(summary: dict[str, Any], *, reason: str | None = None) -> str:
    theme_titles = ", ".join(item["title"] for item in summary.get("themes", [])[:4]) or "none"
    cleanup_titles = ", ".join(item["title"] for item in summary.get("cleanup_candidates", [])[:3]) or "none"
    staged_titles = ", ".join(item["title"] for item in summary.get("staged_notes", [])[:3]) or "none"
    lines = ["Vault organizer"]
    if reason:
        lines.append(f"- reason: {reason}")
    lines.extend(
        [
            f"- notes considered: {summary.get('notes_considered', 0)}",
            f"- normalized notes: {len(summary.get('normalized_notes', []))}",
            f"- staged loose notes: {staged_titles}",
            f"- related links touched: {sum(1 for item in summary.get('related_links', []) if item.get('source_changed') or item.get('target_changed'))}",
            f"- theme hubs: {theme_titles}",
            f"- cleanup candidates: {cleanup_titles}",
        ]
    )
    return "\n".join(lines)


def run_organizer_pass(config: BotConfig, state: dict[str, Any], *, reason: str, force: bool = False) -> dict[str, Any] | None:
    settings = config.maintenance_settings
    if not settings.get("enabled", True) and not force:
        return None
    organizer_settings = settings.get("organizer") if isinstance(settings.get("organizer"), dict) else {}
    organizer_config = organizer_tool.build_config_from_dict(organizer_settings, timezone_name=config.timezone_name)
    summary = organizer_tool.organize_existing_notes(
        config.vault_path,
        organizer_config,
        memory_path=config.vault_path / config.memory_path,
    )
    maintenance = maintenance_state(state)
    maintenance["last_run_at"] = timestamp_now(config.timezone_name).isoformat()
    maintenance["last_reason"] = reason
    maintenance["new_signal_count"] = 0
    maintenance["last_summary"] = {
        "notes_considered": summary.get("notes_considered", 0),
        "changes": count_organizer_changes(summary),
        "theme_titles": [item["title"] for item in summary.get("themes", [])],
    }
    if settings.get("notify_chat") and count_organizer_changes(summary) > 0:
        chat_id = config.default_chat_id
        if chat_id is not None:
            send_message(config, chat_id, format_organizer_summary(summary, reason=reason))
    return summary


def maintenance_due(config: BotConfig, state: dict[str, Any]) -> tuple[bool, str]:
    settings = config.maintenance_settings
    if not settings.get("enabled", True):
        return False, ""
    maintenance = maintenance_state(state)
    now = timestamp_now(config.timezone_name)
    interval_minutes = max(1, int(settings.get("interval_minutes", 360)))
    min_new_signals = max(0, int(settings.get("min_new_signals", 2)))
    last_run_raw = str(maintenance.get("last_run_at") or "").strip()
    if not last_run_raw:
        return True, "startup"

    try:
        last_run = datetime.fromisoformat(last_run_raw)
    except ValueError:
        return True, "invalid-last-run"

    if now - last_run >= timedelta(minutes=interval_minutes):
        return True, "interval"
    if int(maintenance.get("new_signal_count", 0)) >= min_new_signals > 0:
        return True, "new-signals"
    return False, ""


def poll_maintenance(config: BotConfig, state: dict[str, Any]) -> bool:
    due, reason = maintenance_due(config, state)
    if not due:
        return False
    run_organizer_pass(config, state, reason=reason)
    return True


def help_message() -> str:
    return (
        "Commands\n"
        "/review - short vault review\n"
        "/weekly - weekly review with themes and drafts\n"
        "/stats - compact vault stats\n"
        "/memory - current memory focus\n"
        "/quest - one suggested next action\n"
        "/profile - level, xp, and current progress\n"
        "/skills - top skill progression\n"
        "/health - workout and nutrition snapshot\n"
        "/graph - vault graph and orphan-note summary\n"
        "/infographic - minimal overview image\n"
        "/infographic graph - graph image\n"
        "/infographic health - health image\n"
        "/infographic skills - skillboard image\n"
        "/infographic skill writing - one skill image\n"
        "/infographic workout|nutrition|body - one log image\n"
        "/sanitize - clean old noisy Telegram logs\n"
        "/organize - run vault organizer and orphan-note curation\n"
        "/intake - process local Voice Captures and Inbox markdown files\n"
        "/drafts - list pending routing drafts\n"
        "/approve <draft_id> - publish a pending draft\n"
        "/reject <draft_id> - archive a pending draft\n"
        "/link Source | Target One, Target Two - connect notes bidirectionally\n"
        "/log ... - log skill, workout, food, or body data\n"
        "/reminders - list active reminder rules\n"
        "/ask <вопрос> - ask a question about your vault notes\n"
        "/sync - check chat and process any pending messages\n"
        "/help - show this message\n\n"
        "Examples: `gym: bench 80x5x3`, `food: 2200 kcal 160 protein`, `skill: writing | drafted article`, `weight 82.4`, `sleep 7.5`.\n"
        "Voice messages are supported too: the bot will transcribe them and then route the transcript through the same Obsidian intake.\n"
        "Photos and text documents are supported too: the bot will OCR/analyze them and route the extracted text into Obsidian.\n"
        "Useful signals can also auto-turn into permanent notes in `Идеи`, `Мысли`, `посты`, plus staged or promoted themes."
    )


def respond_to_plain_text(config: BotConfig, text: str) -> str | dict[str, Any]:
    intent = plain_text_query_kind(text)
    if intent == "ask":
        return answer_vault_question(config, text)
    if intent == "approve":
        payload = text.split(" ", 1)[1].strip() if " " in text else ""
        return approve_draft(config, payload)
    if intent == "reject":
        payload = text.split(" ", 1)[1].strip() if " " in text else ""
        return reject_draft(config, payload)
    if intent == "link":
        payload = text.split(" ", 1)[1].strip() if " " in text else ""
        return connect_notes_from_argument(config, payload)
    if intent == "infographic":
        return create_infographic_response(config, text)
    if intent == "quest":
        return format_quest_message(config)
    if intent == "review":
        summary = build_summary(config)
        summary["dormant_candidates"] = filter_candidate_notes(config, summary.get("dormant_candidates", []))
        summary["project_candidates"] = filter_candidate_notes(config, summary.get("project_candidates", []))
        summary["cleanup_candidates"] = filter_candidate_notes(config, summary.get("cleanup_candidates", []))
        return format_review_message(summary)
    if intent == "intake":
        return "Use `/intake` to process local Voice Captures and Inbox notes."
    if intent == "weekly":
        return format_weekly_review_message(config)
    if intent == "stats":
        summary = head_tool.stats_only(build_summary(config))
        return format_stats_message(summary)
    if intent == "memory":
        return format_memory_message(config)
    if intent == "profile":
        return format_profile_message(config)
    if intent == "skills":
        return format_skills_message(config)
    if intent == "health":
        return format_health_message(config)
    if intent == "graph":
        return format_graph_message(config)
    if intent == "drafts":
        return format_drafts_message(config)
    if intent == "reminders":
        return format_reminders_message(config)
    if intent == "organize":
        return "Use `/organize` to run the vault organizer explicitly."
    if intent == "sync":
        return "Проверяю чат и обрабатываю ожидающие сообщения…"
    return config.acknowledgement


def handle_command(config: BotConfig, chat_id: int, text: str, state: dict[str, Any] | None = None) -> str | dict[str, Any]:
    command = text.split(maxsplit=1)[0].casefold()
    argument = text.split(maxsplit=1)[1].strip() if len(text.split(maxsplit=1)) == 2 else ""
    if command in {"/start", "/help"}:
        return help_message()
    if command == "/stats":
        summary = head_tool.stats_only(build_summary(config))
        return format_stats_message(summary)
    if command == "/review":
        summary = build_summary(config)
        summary["dormant_candidates"] = filter_candidate_notes(config, summary.get("dormant_candidates", []))
        summary["project_candidates"] = filter_candidate_notes(config, summary.get("project_candidates", []))
        summary["cleanup_candidates"] = filter_candidate_notes(config, summary.get("cleanup_candidates", []))
        return format_review_message(summary)
    if command == "/weekly":
        return format_weekly_review_message(config)
    if command == "/memory":
        return format_memory_message(config)
    if command == "/quest":
        return format_quest_message(config)
    if command == "/profile":
        return format_profile_message(config)
    if command == "/skills":
        return format_skills_message(config)
    if command == "/health":
        return format_health_message(config)
    if command == "/graph":
        return format_graph_message(config)
    if command == "/infographic":
        return create_infographic_response(config, argument)
    if command == "/link":
        return connect_notes_from_argument(config, argument)
    if command == "/log":
        if not argument:
            return "Use `/log ...` with something like `skill: writing | drafted article` or `food: 2200 kcal 160 protein`."
        logged = log_tracking_text(config, argument)
        if logged:
            return logged
        return "I couldn't parse that log entry. Try `gym: bench 80x5x3`, `food: 2200 kcal 160 protein`, `skill: writing | drafted article`, or `weight 82.4`."
    if command == "/sanitize":
        date_filter = None
        lowered_argument = argument.casefold()
        if argument and lowered_argument not in {"all", "legacy"}:
            if lowered_argument in {"today", "сегодня"}:
                date_filter = timestamp_now(config.timezone_name).strftime("%Y-%m-%d")
            else:
                date_filter = argument
        summary = sanitize_legacy_captures(config, date_filter=date_filter)
        return format_sanitize_summary(summary)
    if command == "/intake":
        local_state = state if state is not None else {"local_intake": {}}
        summary = poll_local_intake(config, local_state, force=True)
        return format_local_intake_summary(summary or {"processed": 0, "items": []})
    if command == "/organize":
        local_state = state if state is not None else {"maintenance": {"new_signal_count": 0}}
        summary = run_organizer_pass(config, local_state, reason="manual-command", force=True)
        if summary is None:
            return "Organizer is disabled."
        return format_organizer_summary(summary, reason="manual-command")
    if command == "/drafts":
        return format_drafts_message(config)
    if command == "/approve":
        if not argument:
            return "Укажи draft id. Посмотреть можно через `/drafts`."
        return approve_draft(config, argument)
    if command == "/reject":
        if not argument:
            return "Укажи draft id. Посмотреть можно через `/drafts`."
        return reject_draft(config, argument)
    if command == "/reminders":
        return format_reminders_message(config)
    if command == "/ask":
        if not argument:
            return "Напиши вопрос после /ask, например: `/ask что по проекту дизайна?`"
        return answer_vault_question(config, argument)
    if command == "/sync":
        if state is not None:
            state["sync_requested"] = True
        return "Проверяю чат и обрабатываю ожидающие сообщения…"
    return "Unknown command.\n\n" + help_message()


def check_authorized(config: BotConfig, chat_id: int) -> bool:
    if not config.allowed_chat_ids:
        return True
    return chat_id in config.allowed_chat_ids


def process_message(config: BotConfig, message: dict[str, Any], state: dict[str, Any] | None = None) -> None:
    chat = message.get("chat") or {}
    chat_id = int(chat.get("id"))
    if not check_authorized(config, chat_id):
        return

    sender = format_sender(message)
    text = str(message.get("text") or "").strip()
    source_kind = "text"
    capture_text = text
    extra_meta: dict[str, Any] | None = None
    attachment: MediaAttachment | None = None
    captured_path: Path | None = None
    routed_signal: dict[str, Any] | None = None

    if not text:
        attachment = extract_audio_attachment(message)
        if attachment is not None:
            try:
                text = transcribe_attachment(config, attachment).strip()
            except BotError as exc:
                send_message(config, chat_id, f"Не смог разобрать голосовое.\n\n{exc}")
                return
            if not text:
                send_message(config, chat_id, "Голосовое получил, но речь распознать не удалось.")
                return
            source_kind = attachment.kind
            capture_text = format_transcript_for_capture(text)
            extra_meta = {
                "source": attachment.kind,
                "duration_sec": attachment.duration_seconds,
                "transcript_model": f"whisper/{config.voice_model}",
            }
        else:
            attachment = extract_visual_attachment(message)
            if attachment is None:
                return
            try:
                text = analyze_visual_attachment(config, attachment).strip()
            except BotError as exc:
                send_message(config, chat_id, f"Не смог разобрать фото или документ.\n\n{exc}")
                return
            if not text:
                send_message(
                    config,
                    chat_id,
                    "Фото получил, но текста или понятного документа не нашёл. Добавь подпись или пришли более читаемый документ.",
                )
                return
            source_kind = attachment.kind
            capture_text = format_visual_capture_text(attachment, text)
            extra_meta = {
                "source": attachment.kind,
                "mime_type": attachment.mime_type,
                "analysis_model": "vision-ocr" if attachment.kind != "pdf-document" else "pdftotext",
            }

    decision = classify_incoming_text(config, text)
    if decision.capture:
        captured_path = append_capture_entry(
            config,
            bucket=decision.bucket,
            direction="incoming",
            chat_id=chat_id,
            sender=sender,
            text=capture_text,
            extra_meta=extra_meta,
        )
        if decision.bucket == "signal":
            try:
                routed_signal = signal_router.route_signal(
                    vault=config.vault_path,
                    text=text,
                    source_path=captured_path,
                    memory_path=config.vault_path / config.memory_path,
                    timezone_name=config.timezone_name,
                    routing_settings=config.routing_settings,
                    llm_config=config.llm_config,
                )
                if state is not None and routed_signal and routed_signal.get("routed") and routed_signal.get("published", True):
                    maintenance = maintenance_state(state)
                    maintenance["new_signal_count"] = int(maintenance.get("new_signal_count", 0)) + 1
            except Exception as exc:
                print(f"[signal-router] {exc}", file=sys.stderr)

    if source_kind == "text" and text.startswith("/"):
        response = handle_command(config, chat_id, text, state=state)
    else:
        tracking_response = log_tracking_text(config, text)
        if tracking_response is not None:
            response = tracking_response
        elif routed_signal and routed_signal.get("routed"):
            base_response = format_routed_signal_message(routed_signal)
            smart = ollama_bridge.llm_smart_reply(
                config.llm_config,
                text,
                note_kind=str(routed_signal.get("note_kind", "signal")),
                note_path=str(routed_signal.get("note_path", "")),
                topic_title=str((routed_signal.get("topic") or {}).get("title", "")),
            )
            response = smart if smart else base_response
        elif decision.capture and decision.bucket in {"signal", "personal"}:
            smart = ollama_bridge.llm_smart_reply(
                config.llm_config,
                text,
                note_kind=decision.bucket,
                note_path=decision.bucket,
            )
            response = smart if smart else config.acknowledgement
        elif (intent := plain_text_query_kind(text)) is not None:
            if intent == "sync" and state is not None:
                state["sync_requested"] = True
            response = respond_to_plain_text(config, text)
        elif decision.bucket == "noise":
            response = config.noise_acknowledgement
        else:
            response = config.acknowledgement

    if attachment is not None and source_kind in {"voice", "audio", "audio-document"}:
        response = wrap_voice_response(config, response)
    elif attachment is not None and source_kind != "text":
        response = wrap_visual_response(config, response, attachment)

    logged_text = deliver_response(config, chat_id, response)
    if config.capture_bot_messages and decision.capture:
        append_capture_entry(
            config,
            bucket=decision.bucket,
            direction="bot",
            chat_id=chat_id,
            sender="obsidian-bot",
            text=logged_text,
        )


def parse_legacy_capture_entries(path: Path) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for line in read_text(path).splitlines():
        stripped = line.rstrip("\n")
        if stripped.startswith("## "):
            if current is not None:
                entries.append(current)
            match = re.match(r"##\s+(\d{2}:\d{2}:\d{2})\s+\[([^\]]+)\]", stripped)
            current = {
                "time": match.group(1) if match else "00:00:00",
                "direction": match.group(2) if match else "unknown",
                "meta": {},
                "body_lines": [],
            }
            continue
        if current is None:
            continue
        if stripped.startswith("- ") and ":" in stripped and not current["body_lines"]:
            key, value = stripped[2:].split(":", 1)
            current["meta"][key.strip()] = value.strip()
            continue
        current["body_lines"].append(stripped)
    if current is not None:
        entries.append(current)

    parsed: list[dict[str, Any]] = []
    for entry in entries:
        text_lines: list[str] = []
        for raw_line in entry.get("body_lines", []):
            if raw_line.startswith("> "):
                text_lines.append(raw_line[2:])
            elif raw_line == ">":
                text_lines.append("")
        parsed.append(
            {
                "time": entry.get("time", "00:00:00"),
                "direction": entry.get("direction", "unknown"),
                "chat_id": int(entry.get("meta", {}).get("chat_id", 0) or 0),
                "sender": str(entry.get("meta", {}).get("sender", "unknown")),
                "text": "\n".join(text_lines).strip(),
            }
        )
    return parsed


def legacy_entry_timestamp(config: BotConfig, path: Path, time_value: str) -> datetime:
    local = datetime.fromisoformat(f"{path.stem}T{time_value}")
    return local.replace(tzinfo=resolve_timezone(config.timezone_name))


def unique_destination(path: Path) -> Path:
    if not path.exists():
        return path
    for index in range(2, 1000):
        candidate = path.with_name(f"{path.stem}-{index}{path.suffix}")
        if not candidate.exists():
            return candidate
    raise BotError(f"Could not allocate archive path for {path}")


def archive_legacy_capture(config: BotConfig, path: Path) -> Path:
    archive_root = config.vault_path / config.archive_directory
    archive_root.mkdir(parents=True, exist_ok=True)
    destination = unique_destination(archive_root / f"{path.stem}.raw.md")
    path.rename(destination)
    return destination


def sanitize_legacy_capture_file(config: BotConfig, path: Path) -> dict[str, Any]:
    entries = parse_legacy_capture_entries(path)
    stats = {
        "file": path.name,
        "processed": 0,
        "signal": 0,
        "personal": 0,
        "noise": 0,
        "tracking": 0,
        "queries": 0,
        "commands": 0,
        "skipped_bot": 0,
    }
    for entry in entries:
        if entry["direction"] != "incoming":
            stats["skipped_bot"] += 1
            continue
        stats["processed"] += 1
        text = str(entry.get("text") or "").strip()
        decision = classify_incoming_text(config, text)
        if decision.bucket == "tracking":
            stats["tracking"] += 1
            continue
        if decision.reason == "query":
            stats["queries"] += 1
            continue
        if decision.reason == "command":
            stats["commands"] += 1
            if not config.capture_commands:
                continue
        if decision.bucket == "noise":
            stats["noise"] += 1
            if not config.capture_noise:
                continue
        if not decision.capture:
            continue

        timestamp = legacy_entry_timestamp(config, path, str(entry["time"]))
        append_capture_entry(
            config,
            bucket=decision.bucket,
            direction="incoming",
            chat_id=int(entry.get("chat_id") or config.default_chat_id or 0),
            sender=str(entry.get("sender") or "legacy"),
            text=text,
            now=timestamp,
        )
        if decision.bucket == "personal":
            stats["personal"] += 1
        elif decision.bucket == "signal":
            stats["signal"] += 1

    archive_path = archive_legacy_capture(config, path)
    stats["archive_path"] = archive_path.relative_to(config.vault_path).as_posix()
    return stats


def sanitize_legacy_captures(config: BotConfig, date_filter: str | None = None) -> dict[str, Any]:
    root = config.vault_path / config.capture_directory
    if not root.exists():
        return {"processed_files": 0, "results": []}

    candidates = sorted(item for item in root.glob("*.md") if item.is_file())
    if date_filter:
        candidates = [item for item in candidates if item.stem == date_filter]

    results = [sanitize_legacy_capture_file(config, path) for path in candidates]
    return {
        "processed_files": len(results),
        "results": results,
        "signal": sum(int(item["signal"]) for item in results),
        "personal": sum(int(item["personal"]) for item in results),
        "noise": sum(int(item["noise"]) for item in results),
        "tracking": sum(int(item["tracking"]) for item in results),
        "queries": sum(int(item["queries"]) for item in results),
        "commands": sum(int(item["commands"]) for item in results),
    }


def format_sanitize_summary(summary: dict[str, Any]) -> str:
    if not summary.get("processed_files"):
        return "No legacy Telegram logs needed sanitizing."
    first_archive = summary["results"][0].get("archive_path") if summary.get("results") else None
    lines = [
        "Telegram sanitizer",
        f"- processed files: {summary['processed_files']}",
        f"- kept signal: {summary.get('signal', 0)}",
        f"- kept personal: {summary.get('personal', 0)}",
        f"- discarded noise: {summary.get('noise', 0)}",
        f"- skipped queries: {summary.get('queries', 0)}",
        f"- skipped commands: {summary.get('commands', 0)}",
        f"- skipped tracking duplicates: {summary.get('tracking', 0)}",
    ]
    if first_archive:
        lines.append(f"- archived raw log: {first_archive}")
    return "\n".join(lines)


def is_due(reminder: ReminderRule, state: dict[str, Any], now_utc: datetime, default_chat_id: int | None) -> tuple[bool, str, int | None]:
    if not reminder.enabled:
        return False, "", None
    zone = resolve_timezone(reminder.timezone_name)
    current_local = now_utc.astimezone(zone)
    if reminder.days and current_local.weekday() not in reminder.days:
        return False, "", None
    if (current_local.hour, current_local.minute) < (reminder.hour, reminder.minute):
        return False, "", None
    chat_id = reminder.chat_id if reminder.chat_id is not None else default_chat_id
    if chat_id is None:
        return False, "", None

    reminder_state = state.setdefault("reminders", {})
    chat_key = str(chat_id)
    last_sent = reminder_state.get(chat_key, {}).get(reminder.reminder_id)
    today_key = current_local.strftime("%Y-%m-%d")
    return last_sent != today_key, today_key, chat_id


def mark_reminder_sent(state: dict[str, Any], reminder_id: str, chat_id: int, date_key: str) -> None:
    reminder_state = state.setdefault("reminders", {})
    reminder_state.setdefault(str(chat_id), {})[reminder_id] = date_key


def render_reminder_text(config: BotConfig, reminder: ReminderRule) -> str:
    summary = build_summary(config)
    return reminder.message.format(
        date=timestamp_now(reminder.timezone_name).strftime("%Y-%m-%d"),
        quest=suggest_quest(config, summary=summary),
    ).strip()


def poll_reminders(config: BotConfig, state: dict[str, Any]) -> bool:
    changed = False
    now_utc = datetime.now(timezone.utc)
    for reminder in config.reminders:
        due, date_key, chat_id = is_due(reminder, state, now_utc, config.default_chat_id)
        if not due or chat_id is None:
            continue
        message = render_reminder_text(config, reminder)
        send_message(config, chat_id, message)
        if config.capture_bot_messages:
            append_capture_entry(
                config,
                bucket="signal",
                direction="bot",
                chat_id=chat_id,
                sender="obsidian-bot",
                text=message,
            )
        mark_reminder_sent(state, reminder.reminder_id, chat_id, date_key)
        changed = True
    return changed


def run_bot(config_path: Path) -> int:
    config = load_config(config_path)
    ensure_memory_file(config)
    state = load_state(config.state_path)
    local_wake = threading.Event()
    start_local_intake_watcher(config, local_wake)

    while True:
        # Telegram updates first — so missed messages are processed immediately on startup
        offset = int(state.get("last_update_id", 0)) + 1
        updates = get_updates(config, offset)
        for update in updates:
            update_id = int(update.get("update_id", 0))
            state["last_update_id"] = max(int(state.get("last_update_id", 0)), update_id)
            message = update.get("message")
            if isinstance(message, dict):
                process_message(config, message, state=state)
            save_state(config.state_path, state)

        # Extra fetch when user requested /sync
        if state.pop("sync_requested", False):
            offset = int(state.get("last_update_id", 0)) + 1
            extra = get_updates(config, offset)
            for update in extra:
                update_id = int(update.get("update_id", 0))
                state["last_update_id"] = max(int(state.get("last_update_id", 0)), update_id)
                message = update.get("message")
                if isinstance(message, dict):
                    process_message(config, message, state=state)
                save_state(config.state_path, state)

        local_force = local_wake.is_set()
        if local_force:
            local_wake.clear()
        local_summary = poll_local_intake(config, state, force=local_force)
        if local_summary is not None:
            save_state(config.state_path, state)
        if poll_reminders(config, state):
            save_state(config.state_path, state)
        if poll_maintenance(config, state):
            save_state(config.state_path, state)

        if not updates:
            time.sleep(1)


def command_run(args: argparse.Namespace) -> int:
    try:
        return run_bot(Path(args.config).expanduser().resolve())
    except KeyboardInterrupt:
        return 0


def command_once(args: argparse.Namespace) -> int:
    config = load_config(Path(args.config).expanduser().resolve())
    ensure_memory_file(config)
    state = load_state(config.state_path)
    changed = poll_reminders(config, state)
    local_summary = poll_local_intake(config, state)
    changed = local_summary is not None or changed
    changed = poll_maintenance(config, state) or changed
    if changed:
        save_state(config.state_path, state)
    summary = build_summary(config)
    output = {
        "memory_path": str((config.vault_path / config.memory_path).resolve()),
        "quest": suggest_quest(config, summary=summary),
        "profile": build_tracking_summary(config),
        "weekly": build_weekly_review_data(config),
        "review": {
            "dormant_candidates": filter_candidate_notes(config, summary.get("dormant_candidates", [])),
            "project_candidates": filter_candidate_notes(config, summary.get("project_candidates", [])),
            "cleanup_candidates": filter_candidate_notes(config, summary.get("cleanup_candidates", [])),
        },
    }
    sys.stdout.write(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    return 0


def command_sanitize(args: argparse.Namespace) -> int:
    config = load_config(Path(args.config).expanduser().resolve())
    date_filter = args.date
    if date_filter and date_filter.casefold() in {"today", "сегодня"}:
        date_filter = timestamp_now(config.timezone_name).strftime("%Y-%m-%d")
    summary = sanitize_legacy_captures(config, date_filter=date_filter)
    sys.stdout.write(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Telegram bridge for the Obsidian Head Agent.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    run_parser = subparsers.add_parser("run", help="Run the Telegram bot loop with long polling.")
    run_parser.add_argument("config", help="Path to the Telegram bot JSON config")
    run_parser.set_defaults(func=command_run)

    once_parser = subparsers.add_parser("once", help="Run one local review cycle without polling Telegram.")
    once_parser.add_argument("config", help="Path to the Telegram bot JSON config")
    once_parser.set_defaults(func=command_once)

    sanitize_parser = subparsers.add_parser("sanitize", help="Sanitize legacy Telegram daily logs into clean buckets.")
    sanitize_parser.add_argument("config", help="Path to the Telegram bot JSON config")
    sanitize_parser.add_argument("--date", help="Optional YYYY-MM-DD filter, or `today`.")
    sanitize_parser.set_defaults(func=command_sanitize)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except BotError as exc:
        parser.exit(status=1, message=f"{exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
