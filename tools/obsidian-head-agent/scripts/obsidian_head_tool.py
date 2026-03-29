#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

IGNORED_DIRS = {
    ".git",
    ".obsidian",
    ".trash",
    "__pycache__",
    "node_modules",
}

STOPWORDS = {
    "the",
    "and",
    "for",
    "with",
    "that",
    "this",
    "from",
    "into",
    "about",
    "your",
    "have",
    "what",
    "when",
    "where",
    "как",
    "что",
    "это",
    "для",
    "или",
    "надо",
    "если",
    "когда",
    "быть",
    "idea",
    "ideas",
    "note",
    "notes",
}

PROJECT_KEYWORDS = {
    "project",
    "roadmap",
    "launch",
    "plan",
    "build",
    "ship",
    "initiative",
    "delivery",
    "проект",
    "план",
    "запуск",
}

IDEA_KEYWORDS = {
    "idea",
    "concept",
    "hypothesis",
    "experiment",
    "research",
    "thesis",
    "brainstorm",
    "идея",
    "идеям",
    "гипотеза",
    "мысль",
    "эксперимент",
}

TASK_PATTERN = re.compile(r"^\s*[-*]\s+\[(?P<done>[ xX])\]\s+", re.MULTILINE)
WIKILINK_PATTERN = re.compile(r"\[\[([^\]]+)\]\]")
INLINE_TAG_PATTERN = re.compile(r"(?<![\w`])#([\w\-/]+)")
FRONTMATTER_PATTERN = re.compile(r"^---\n(.*?)\n---\n?", re.DOTALL)


class VaultError(Exception):
    pass


@dataclass
class NoteRecord:
    path: Path
    rel_path: str
    rel_link: str
    stem: str
    title: str
    tags: list[str]
    aliases: list[str]
    word_count: int
    open_tasks: int
    done_tasks: int
    outbound_links: list[str]
    modified_at: datetime
    has_frontmatter: bool

    def to_summary(self) -> dict[str, object]:
        return {
            "title": self.title,
            "path": self.rel_path,
            "tags": self.tags,
            "open_tasks": self.open_tasks,
            "done_tasks": self.done_tasks,
            "word_count": self.word_count,
            "outbound_links": len(self.outbound_links),
            "modified_at": self.modified_at.isoformat(),
        }


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def normalize_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold().strip()
    normalized = normalized.replace("_", " ")
    normalized = re.sub(r"\s+", " ", normalized)
    return normalized


def normalize_path(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold().strip()
    normalized = normalized.replace("\\", "/")
    normalized = re.sub(r"/+", "/", normalized).strip("/")
    if normalized.endswith(".md"):
        normalized = normalized[:-3]
    return normalized


def as_list(value: object) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str):
        stripped = value.strip()
        return [stripped] if stripped else []
    return []


def strip_quotes(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def parse_inline_list(value: str) -> list[str]:
    inner = value[1:-1].strip()
    if not inner:
        return []
    return [strip_quotes(item.strip()) for item in inner.split(",") if item.strip()]


def parse_frontmatter(block: str) -> dict[str, object]:
    data: dict[str, object] = {}
    lines = block.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or ":" not in line:
            index += 1
            continue
        key, raw_value = line.split(":", 1)
        key = key.strip()
        value = raw_value.strip()
        if value.startswith("[") and value.endswith("]"):
            data[key] = parse_inline_list(value)
            index += 1
            continue
        if value:
            data[key] = strip_quotes(value)
            index += 1
            continue
        items: list[str] = []
        index += 1
        while index < len(lines):
            nested = lines[index]
            nested_stripped = nested.strip()
            if not nested_stripped:
                index += 1
                continue
            if re.match(r"^\s*-\s+", nested):
                item = re.sub(r"^\s*-\s+", "", nested).strip()
                items.append(strip_quotes(item))
                index += 1
                continue
            break
        data[key] = items
    return data


def split_frontmatter(text: str) -> tuple[dict[str, object], str, bool]:
    match = FRONTMATTER_PATTERN.match(text)
    if not match:
        return {}, text, False
    return parse_frontmatter(match.group(1)), text[match.end() :], True


def first_heading(body: str) -> str | None:
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("# "):
            return stripped[2:].strip()
    return None


def iter_markdown_files(vault: Path) -> list[Path]:
    files: list[Path] = []
    for path in vault.rglob("*.md"):
        relative_parts = path.relative_to(vault).parts[:-1]
        if any(part in IGNORED_DIRS for part in relative_parts):
            continue
        files.append(path)
    return sorted(files)


def extract_wikilinks(text: str) -> list[str]:
    results: list[str] = []
    for match in WIKILINK_PATTERN.finditer(text):
        raw = match.group(1).strip()
        if not raw:
            continue
        raw = raw.split("|", 1)[0].strip()
        raw = raw.split("#", 1)[0].strip()
        if raw and raw not in results:
            results.append(raw)
    return results


def extract_inline_tags(text: str) -> list[str]:
    results: list[str] = []
    for match in INLINE_TAG_PATTERN.finditer(text):
        tag = match.group(1).strip()
        if tag and tag not in results:
            results.append(tag)
    return results


def count_words(text: str) -> int:
    return len(re.findall(r"\b[\w-]+\b", text, re.UNICODE))


def count_tasks(text: str) -> tuple[int, int]:
    open_count = 0
    done_count = 0
    for match in TASK_PATTERN.finditer(text):
        if match.group("done").lower() == "x":
            done_count += 1
        else:
            open_count += 1
    return open_count, done_count


def ensure_vault(path_arg: str) -> Path:
    vault = Path(path_arg).expanduser().resolve()
    if not vault.exists():
        raise VaultError(f"Vault does not exist: {vault}")
    if not vault.is_dir():
        raise VaultError(f"Vault is not a directory: {vault}")
    return vault


def build_notes(vault: Path) -> list[NoteRecord]:
    notes: list[NoteRecord] = []
    for note_path in iter_markdown_files(vault):
        text = read_text(note_path)
        frontmatter, body, has_frontmatter = split_frontmatter(text)
        title = str(frontmatter.get("title") or first_heading(body) or note_path.stem).strip()
        tags = list(dict.fromkeys(as_list(frontmatter.get("tags")) + extract_inline_tags(body)))
        aliases = as_list(frontmatter.get("aliases"))
        outbound_links = extract_wikilinks(body)
        open_tasks, done_tasks = count_tasks(body)
        rel_path = note_path.relative_to(vault).as_posix()
        rel_link = rel_path[:-3] if rel_path.endswith(".md") else rel_path
        notes.append(
            NoteRecord(
                path=note_path,
                rel_path=rel_path,
                rel_link=rel_link,
                stem=note_path.stem,
                title=title,
                tags=tags,
                aliases=aliases,
                word_count=count_words(body),
                open_tasks=open_tasks,
                done_tasks=done_tasks,
                outbound_links=outbound_links,
                modified_at=datetime.fromtimestamp(note_path.stat().st_mtime, tz=timezone.utc),
                has_frontmatter=has_frontmatter,
            )
        )
    return notes


def build_lookup(notes: list[NoteRecord]) -> tuple[dict[str, list[NoteRecord]], dict[str, list[NoteRecord]]]:
    text_lookup: dict[str, list[NoteRecord]] = defaultdict(list)
    path_lookup: dict[str, list[NoteRecord]] = defaultdict(list)
    for note in notes:
        text_keys = {normalize_text(note.title), normalize_text(note.stem)}
        text_keys.update(normalize_text(alias) for alias in note.aliases if alias.strip())
        for key in text_keys:
            if key:
                text_lookup[key].append(note)
        path_keys = {normalize_path(note.rel_path), normalize_path(note.rel_link)}
        for key in path_keys:
            if key:
                path_lookup[key].append(note)
    return dict(text_lookup), dict(path_lookup)


def resolve_target(
    raw_target: str,
    text_lookup: dict[str, list[NoteRecord]],
    path_lookup: dict[str, list[NoteRecord]],
) -> NoteRecord | None:
    path_matches = path_lookup.get(normalize_path(raw_target), [])
    if len(path_matches) == 1:
        return path_matches[0]
    text_matches = text_lookup.get(normalize_text(raw_target), [])
    unique = {note.rel_path: note for note in text_matches}
    if len(unique) == 1:
        return next(iter(unique.values()))
    return None


def title_tokens(title: str) -> list[str]:
    tokens = re.findall(r"[\w-]+", title.casefold(), re.UNICODE)
    return [token for token in tokens if len(token) >= 4 and token not in STOPWORDS]


def candidate_score(note: NoteRecord, keywords: set[str], weight_tasks: bool) -> int:
    title_terms = set(title_tokens(note.title))
    tag_terms = {normalize_text(tag) for tag in note.tags}
    score = 0
    if title_terms & keywords:
        score += 3
    if tag_terms & keywords:
        score += 3
    if weight_tasks:
        score += min(note.open_tasks, 3) * 2
    if note.word_count >= 80:
        score += 1
    if note.outbound_links:
        score += 1
    return score


def summarize_review(notes: list[NoteRecord], days_stale: int, limit: int) -> dict[str, object]:
    now = datetime.now(timezone.utc)
    text_lookup, path_lookup = build_lookup(notes)

    inbound_counts: Counter[str] = Counter()
    total_links = 0
    unresolved_links = 0
    for note in notes:
        for raw_target in note.outbound_links:
            total_links += 1
            target = resolve_target(raw_target, text_lookup, path_lookup)
            if target is None:
                unresolved_links += 1
                continue
            inbound_counts[target.rel_path] += 1

    tag_counter: Counter[str] = Counter()
    folder_counter: Counter[str] = Counter()
    theme_counter: Counter[str] = Counter()
    duplicate_titles: Counter[str] = Counter()
    notes_with_frontmatter = 0
    total_words = 0
    open_tasks = 0
    done_tasks = 0

    for note in notes:
        total_words += note.word_count
        open_tasks += note.open_tasks
        done_tasks += note.done_tasks
        if note.has_frontmatter:
            notes_with_frontmatter += 1
        for tag in note.tags:
            tag_counter[tag] += 1
            theme_counter[tag] += 1
        for token in title_tokens(note.title):
            theme_counter[token] += 1
        top_folder = Path(note.rel_path).parts[0] if len(Path(note.rel_path).parts) > 1 else "."
        folder_counter[top_folder] += 1
        duplicate_titles[normalize_text(note.title)] += 1

    recent_notes = sorted(notes, key=lambda note: note.modified_at, reverse=True)[:limit]
    stale_notes = [
        note
        for note in sorted(notes, key=lambda note: note.modified_at)
        if (now - note.modified_at).days >= days_stale
    ][:limit]

    orphan_notes = [
        note
        for note in sorted(notes, key=lambda note: (inbound_counts[note.rel_path], len(note.outbound_links), note.title))
        if inbound_counts[note.rel_path] == 0 and len(note.outbound_links) == 0
    ][:limit]

    duplicate_note_candidates = [
        note
        for note in notes
        if duplicate_titles[normalize_text(note.title)] > 1
    ]

    project_candidates = sorted(
        (
            (candidate_score(note, PROJECT_KEYWORDS, weight_tasks=True), note)
            for note in notes
        ),
        key=lambda pair: (pair[0], pair[1].open_tasks, pair[1].modified_at),
        reverse=True,
    )
    project_candidates = [note for score, note in project_candidates if score >= 3][:limit]

    idea_candidates = sorted(
        (
            (candidate_score(note, IDEA_KEYWORDS, weight_tasks=False), note)
            for note in notes
        ),
        key=lambda pair: (pair[0], pair[1].word_count, pair[1].modified_at),
        reverse=True,
    )
    idea_candidates = [note for score, note in idea_candidates if score >= 3][:limit]

    dormant_candidates = [
        note
        for note in stale_notes
        if note in project_candidates
        or note in idea_candidates
        or note.open_tasks > 0
    ][:limit]

    cleanup_candidates = [
        note
        for note in notes
        if (
            note.word_count <= 25
            and note.open_tasks == 0
            and note.done_tasks == 0
            and not note.outbound_links
            and inbound_counts[note.rel_path] == 0
        )
    ]
    cleanup_candidates.extend(duplicate_note_candidates)
    unique_cleanup: list[NoteRecord] = []
    seen_cleanup: set[str] = set()
    for note in cleanup_candidates:
        if note.rel_path in seen_cleanup:
            continue
        seen_cleanup.add(note.rel_path)
        unique_cleanup.append(note)
    cleanup_candidates = unique_cleanup[:limit]

    return {
        "vault_generated_at": now.isoformat(),
        "totals": {
            "notes": len(notes),
            "words": total_words,
            "links": total_links,
            "unresolved_links": unresolved_links,
            "unique_tags": len(tag_counter),
            "notes_with_frontmatter": notes_with_frontmatter,
            "tasks_open": open_tasks,
            "tasks_done": done_tasks,
        },
        "top_tags": [{"tag": tag, "count": count} for tag, count in tag_counter.most_common(limit)],
        "top_folders": [{"folder": folder, "count": count} for folder, count in folder_counter.most_common(limit)],
        "themes": [{"theme": theme, "count": count} for theme, count in theme_counter.most_common(limit)],
        "recent_notes": [note.to_summary() for note in recent_notes],
        "stale_notes": [note.to_summary() for note in stale_notes],
        "orphan_notes": [note.to_summary() for note in orphan_notes],
        "project_candidates": [note.to_summary() for note in project_candidates],
        "idea_candidates": [note.to_summary() for note in idea_candidates],
        "dormant_candidates": [note.to_summary() for note in dormant_candidates],
        "cleanup_candidates": [note.to_summary() for note in cleanup_candidates],
    }


def stats_only(summary: dict[str, object]) -> dict[str, object]:
    return {
        "vault_generated_at": summary["vault_generated_at"],
        "totals": summary["totals"],
        "top_tags": summary["top_tags"],
        "top_folders": summary["top_folders"],
        "themes": summary["themes"],
        "recent_notes": summary["recent_notes"],
    }


def format_markdown(data: dict[str, object], mode: str) -> str:
    totals = data["totals"]
    lines = [
        f"# Vault {mode.title()}",
        "",
        "## Totals",
        f"- Notes: {totals['notes']}",
        f"- Words: {totals['words']}",
        f"- Links: {totals['links']}",
        f"- Unresolved links: {totals['unresolved_links']}",
        f"- Unique tags: {totals['unique_tags']}",
        f"- Notes with frontmatter: {totals['notes_with_frontmatter']}",
        f"- Open tasks: {totals['tasks_open']}",
        f"- Completed tasks: {totals['tasks_done']}",
        "",
    ]

    def add_section(title: str, items: list[dict[str, object]], key: str) -> None:
        lines.append(f"## {title}")
        if not items:
            lines.append("- None")
            lines.append("")
            return
        for item in items:
            if key in item and "count" in item:
                lines.append(f"- {item[key]}: {item['count']}")
            else:
                lines.append(f"- {item['title']} ({item['path']})")
        lines.append("")

    add_section("Top Tags", data.get("top_tags", []), "tag")
    add_section("Top Folders", data.get("top_folders", []), "folder")
    add_section("Themes", data.get("themes", []), "theme")
    add_section("Recent Notes", data.get("recent_notes", []), "title")

    if mode == "review":
        add_section("Stale Notes", data.get("stale_notes", []), "title")
        add_section("Orphan Notes", data.get("orphan_notes", []), "title")
        add_section("Project Candidates", data.get("project_candidates", []), "title")
        add_section("Idea Candidates", data.get("idea_candidates", []), "title")
        add_section("Dormant Candidates", data.get("dormant_candidates", []), "title")
        add_section("Cleanup Candidates", data.get("cleanup_candidates", []), "title")

    return "\n".join(lines).rstrip() + "\n"


def render_output(data: dict[str, object], mode: str, output_format: str) -> str:
    if output_format == "json":
        return json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    return format_markdown(data, mode)


def default_memory_template() -> str:
    template_path = Path(__file__).resolve().parent.parent / "assets" / "Memory.md"
    if template_path.exists():
        return read_text(template_path)
    return "# Memory\n"


def command_init_memory(args: argparse.Namespace) -> int:
    vault = ensure_vault(args.vault)
    memory_path = vault / args.memory_path
    if memory_path.exists() and not args.force:
        raise VaultError(f"Memory file already exists: {memory_path}")
    write_text(memory_path, default_memory_template())
    sys.stdout.write(str(memory_path) + "\n")
    return 0


def command_stats(args: argparse.Namespace) -> int:
    vault = ensure_vault(args.vault)
    notes = build_notes(vault)
    summary = summarize_review(notes, days_stale=args.days_stale, limit=args.limit)
    sys.stdout.write(render_output(stats_only(summary), "stats", args.format))
    return 0


def command_review(args: argparse.Namespace) -> int:
    vault = ensure_vault(args.vault)
    notes = build_notes(vault)
    summary = summarize_review(notes, days_stale=args.days_stale, limit=args.limit)
    sys.stdout.write(render_output(summary, "review", args.format))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Obsidian Head Agent helper utilities.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    init_memory = subparsers.add_parser("init-memory", help="Create Memory.md in a vault.")
    init_memory.add_argument("vault", help="Path to the vault root")
    init_memory.add_argument(
        "--memory-path",
        default="Memory.md",
        help="Path relative to the vault where Memory.md should be written",
    )
    init_memory.add_argument("--force", action="store_true", help="Overwrite an existing memory file")
    init_memory.set_defaults(func=command_init_memory)

    for name, handler in (("stats", command_stats), ("review", command_review)):
        subparser = subparsers.add_parser(name, help=f"Generate a {name} snapshot for a vault.")
        subparser.add_argument("vault", help="Path to the vault root")
        subparser.add_argument(
            "--format",
            choices=("json", "markdown"),
            default="json",
            help="Output format",
        )
        subparser.add_argument(
            "--days-stale",
            type=int,
            default=45,
            help="Threshold in days for stale notes",
        )
        subparser.add_argument(
            "--limit",
            type=int,
            default=10,
            help="Maximum number of items per section",
        )
        subparser.set_defaults(func=handler)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except VaultError as exc:
        parser.exit(status=1, message=f"{exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
