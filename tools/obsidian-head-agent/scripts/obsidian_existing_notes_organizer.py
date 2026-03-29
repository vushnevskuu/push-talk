#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import obsidian_head_tool as head_tool
import obsidian_signal_router as signal_router


DEFAULT_INCLUDE_DIRS = ["Идеи", "Мысли", "посты", "Мой путь"]
DEFAULT_CLEANUP_PREFIXES = ["Voice Captures/Inbox", "Voice Captures/Ideas"]
DEFAULT_EXCLUDE_PREFIXES = ["Inbox/Telegram", "Logs/Tracking", "Reports/Infographics", "Темы"]
DEFAULT_DISTRIBUTION_DIR = "Inbox/Telegram/Распределение/Legacy"

CLEANUP_TITLE_HINTS = ("тест", "test", "запись", "recording", "raw", "temp")
SPECIAL_THEME_TITLES = {
    "мой путь": "Личный путь дизайнера",
    "идеи": "Продуктовые идеи",
    "посты": "Посты и контент",
    "мысли": "Мысли и наблюдения",
}
ORGANIZER_STOPWORDS = {
    "вот",
    "его",
    "так",
    "свой",
    "своя",
    "свои",
    "можно",
    "штука",
    "который",
    "которая",
    "которые",
    "моему",
    "меня",
    "очень",
    "мне",
    "только",
    "работе",
    "работа",
    "результат",
    "камеру",
    "настроение",
    "related",
    "summary",
    "signals",
    "notes",
}


class OrganizerError(Exception):
    pass


@dataclass
class OrganizerConfig:
    include_dirs: list[str]
    exclude_prefixes: list[str]
    cleanup_prefixes: list[str]
    theme_directory: str
    distribution_directory: str
    timezone_name: str
    max_related: int
    min_link_score: int
    min_theme_score: int
    cleanup_min_words: int


@dataclass
class ExistingNote:
    rel_path: str
    title: str
    folder: str
    path: Path
    text: str
    words: int
    title_tokens: list[str]
    all_tokens: list[str]
    title_signatures: set[str]
    all_signatures: set[str]
    signature_forms: dict[str, str]


def build_config(args: argparse.Namespace) -> OrganizerConfig:
    include_dirs = parse_csv_values(args.include) or list(DEFAULT_INCLUDE_DIRS)
    exclude_prefixes = parse_csv_values(args.exclude) or list(DEFAULT_EXCLUDE_PREFIXES)
    cleanup_prefixes = parse_csv_values(args.cleanup) or list(DEFAULT_CLEANUP_PREFIXES)
    return OrganizerConfig(
        include_dirs=include_dirs,
        exclude_prefixes=exclude_prefixes,
        cleanup_prefixes=cleanup_prefixes,
        theme_directory=args.theme_dir,
        distribution_directory=args.distribution_dir,
        timezone_name=args.timezone,
        max_related=args.max_related,
        min_link_score=args.min_link_score,
        min_theme_score=args.min_theme_score,
        cleanup_min_words=args.cleanup_min_words,
    )


def build_config_from_dict(settings: dict[str, Any] | None, *, timezone_name: str = "Asia/Bangkok") -> OrganizerConfig:
    data = settings or {}
    include_dirs = parse_csv_values(data.get("include")) if isinstance(data.get("include"), list) else parse_csv_values([str(data.get("include"))]) if data.get("include") else []
    exclude_prefixes = parse_csv_values(data.get("exclude")) if isinstance(data.get("exclude"), list) else parse_csv_values([str(data.get("exclude"))]) if data.get("exclude") else []
    cleanup_prefixes = parse_csv_values(data.get("cleanup")) if isinstance(data.get("cleanup"), list) else parse_csv_values([str(data.get("cleanup"))]) if data.get("cleanup") else []
    return OrganizerConfig(
        include_dirs=include_dirs or list(DEFAULT_INCLUDE_DIRS),
        exclude_prefixes=exclude_prefixes or list(DEFAULT_EXCLUDE_PREFIXES),
        cleanup_prefixes=cleanup_prefixes or list(DEFAULT_CLEANUP_PREFIXES),
        theme_directory=str(data.get("theme_dir") or "Темы"),
        distribution_directory=str(data.get("distribution_dir") or DEFAULT_DISTRIBUTION_DIR),
        timezone_name=str(data.get("timezone") or timezone_name),
        max_related=int(data.get("max_related", 3)),
        min_link_score=int(data.get("min_link_score", 10)),
        min_theme_score=int(data.get("min_theme_score", 10)),
        cleanup_min_words=int(data.get("cleanup_min_words", 12)),
    )


def parse_csv_values(values: list[str] | None) -> list[str]:
    if not values:
        return []
    items: list[str] = []
    for raw in values:
        for part in raw.split(","):
            cleaned = part.strip()
            if cleaned:
                items.append(cleaned)
    return items


def normalize_rel_path(rel_path: str) -> str:
    return head_tool.normalize_path(rel_path)


def starts_with_any(rel_path: str, prefixes: list[str]) -> bool:
    normalized = normalize_rel_path(rel_path)
    for prefix in prefixes:
        normalized_prefix = normalize_rel_path(prefix)
        if not normalized_prefix:
            continue
        if normalized == normalized_prefix or normalized.startswith(normalized_prefix + "/"):
            return True
    return False


def build_existing_notes(vault: Path, config: OrganizerConfig, obsidian_tool: Any) -> list[ExistingNote]:
    index = obsidian_tool.build_index(vault)
    notes: list[ExistingNote] = []
    for note in index.notes:
        rel_path = note.rel_path
        if starts_with_any(rel_path, config.exclude_prefixes):
            continue
        if not starts_with_any(rel_path, config.include_dirs):
            continue
        text = signal_router.read_text(note.path)
        frontmatter, body = obsidian_tool.split_frontmatter(text)
        title = str(frontmatter.get("title") or note.title or note.path.stem).strip()
        folder = rel_path.split("/", 1)[0] if "/" in rel_path else ""
        body_source = strip_related_section(body).strip() or title
        title_tokens = [token for token in signal_router.meaningful_tokens(title) if token not in ORGANIZER_STOPWORDS]
        all_tokens = signal_router.meaningful_tokens(title + "\n" + body_source)
        signature_forms: dict[str, str] = {}
        for token in [*title_tokens, *all_tokens]:
            signature_forms.setdefault(signal_router.token_signature(token), token)
        words = len(body_source.split())
        notes.append(
            ExistingNote(
                rel_path=rel_path,
                title=title,
                folder=folder,
                path=note.path,
                text=text,
                words=words,
                title_tokens=title_tokens,
                all_tokens=all_tokens,
                title_signatures={signal_router.token_signature(token) for token in title_tokens},
                all_signatures={signal_router.token_signature(token) for token in all_tokens},
                signature_forms=signature_forms,
            )
        )
    return notes


def strip_related_section(body: str) -> str:
    marker = "\n## Related"
    if marker not in body:
        return body
    return body.split(marker, 1)[0].rstrip() + "\n"


def note_title_for_record(note_record: Any, text: str, obsidian_tool: Any) -> str:
    frontmatter, _ = obsidian_tool.split_frontmatter(text)
    return str(frontmatter.get("title") or note_record.title or note_record.path.stem).strip()


def root_note_stem_signatures(stem: str) -> set[str]:
    return {
        signal_router.token_signature(token)
        for token in signal_router.meaningful_tokens(stem)
        if token not in ORGANIZER_STOPWORDS
    }


def looks_like_generated_analysis(text: str) -> bool:
    numbered_headings = sum(
        1
        for line in text.splitlines()
        if re.match(r"^\s*#\s+\d+[.)]", line.strip())
    )
    return numbered_headings >= 3


def should_stage_root_note(note_record: Any, text: str, obsidian_tool: Any) -> tuple[bool, str]:
    if note_record.rel_path == "Memory.md" or "/" in note_record.rel_path:
        return False, ""
    title = note_title_for_record(note_record, text, obsidian_tool)
    stem_signatures = root_note_stem_signatures(note_record.path.stem)
    title_signatures = {
        signal_router.token_signature(token)
        for token in signal_router.meaningful_tokens(title)
        if token not in ORGANIZER_STOPWORDS
    }
    if stem_signatures & title_signatures:
        return False, ""

    short_or_gibberish_stem = len(note_record.path.stem.strip()) <= 4 or not stem_signatures
    if short_or_gibberish_stem and len(title_signatures) >= 2:
        return True, "root note had weak filename and was staged for distribution"
    if looks_like_generated_analysis(text):
        return True, "generated analysis note was staged for distribution"
    return False, ""


def available_distribution_path(vault: Path, title: str, config: OrganizerConfig, obsidian_tool: Any, current_path: Path) -> Path:
    base_title = signal_router.safe_note_title(title, fallback="Unsorted Note")
    candidate = obsidian_tool.build_note_path(vault, base_title, None, config.distribution_directory)
    if candidate == current_path or not candidate.exists():
        return candidate
    for index in range(2, 1000):
        candidate = obsidian_tool.build_note_path(vault, f"{base_title} {index}", None, config.distribution_directory)
        if candidate == current_path or not candidate.exists():
            return candidate
    raise OrganizerError(f"Could not find available distribution path for {title}")


def stage_root_notes(vault: Path, config: OrganizerConfig, obsidian_tool: Any) -> list[dict[str, Any]]:
    index = obsidian_tool.build_index(vault)
    moves: list[dict[str, Any]] = []
    for note_record in index.notes:
        text = signal_router.read_text(note_record.path)
        should_stage, reason = should_stage_root_note(note_record, text, obsidian_tool)
        if not should_stage:
            continue
        title = note_title_for_record(note_record, text, obsidian_tool)
        target_path = available_distribution_path(vault, title, config, obsidian_tool, note_record.path)
        target_path.parent.mkdir(parents=True, exist_ok=True)
        note_record.path.rename(target_path)
        moves.append(
            {
                "title": title,
                "from_path": note_record.rel_path,
                "path": target_path.relative_to(vault).as_posix(),
                "reason": reason,
                "classification": "staged-for-routing",
                "suggested_action": "review, rename if needed, and let future signals cluster around it",
                "confirmation_required": "no",
                "resolved_state": "moved",
            }
        )
    return moves


def ensure_note_shell(note: ExistingNote) -> bool:
    stripped = note.text.strip()
    heading = f"# {note.title}\n"
    if not stripped:
        signal_router.write_text(note.path, heading + "\n")
        note.text = signal_router.read_text(note.path)
        note.words = len(note.title.split())
        return True
    if stripped.startswith("## Related") and not note.text.lstrip().startswith("# "):
        signal_router.write_text(note.path, heading + "\n" + note.text.lstrip())
        note.text = signal_router.read_text(note.path)
        note.words = len(note.text.split())
        return True
    return False


def score_note_pair(left: ExistingNote, right: ExistingNote) -> tuple[int, list[str]]:
    shared_title = left.title_signatures & right.title_signatures
    score = len(shared_title) * 20
    if shared_title and left.folder == right.folder:
        score += 4
    return score, sorted(shared_title)


def connect_related_notes(vault: Path, notes: list[ExistingNote], config: OrganizerConfig, obsidian_tool: Any) -> list[dict[str, Any]]:
    index = obsidian_tool.build_index(vault)
    pair_scores: dict[tuple[str, str], tuple[int, list[str]]] = {}
    candidate_map: defaultdict[str, list[tuple[int, str]]] = defaultdict(list)
    for left_index, left in enumerate(notes):
        for right in notes[left_index + 1 :]:
            score, shared = score_note_pair(left, right)
            if score < config.min_link_score:
                continue
            pair_scores[(left.rel_path, right.rel_path)] = (score, shared)
            candidate_map[left.rel_path].append((score, right.rel_path))
            candidate_map[right.rel_path].append((score, left.rel_path))

    selected_edges: set[tuple[str, str]] = set()
    for source_rel, candidates in candidate_map.items():
        candidates.sort(key=lambda item: (item[0], item[1]), reverse=True)
        for _, target_rel in candidates[: config.max_related]:
            edge = tuple(sorted((source_rel, target_rel)))
            selected_edges.add(edge)

    updates: list[dict[str, Any]] = []
    for left_rel, right_rel in sorted(selected_edges):
        left_note = obsidian_tool.resolve_note(index, left_rel)
        right_note = obsidian_tool.resolve_note(index, right_rel)
        left_update = obsidian_tool.update_note_with_links(left_note, [right_note], index.stem_counts, "Related", dry_run=False)
        right_update = obsidian_tool.update_note_with_links(right_note, [left_note], index.stem_counts, "Related", dry_run=False)
        score, shared = pair_scores[(left_rel, right_rel)]
        updates.append(
            {
                "source": left_rel,
                "target": right_rel,
                "score": score,
                "shared_tokens": shared,
                "source_changed": left_update["changed"],
                "target_changed": right_update["changed"],
            }
        )
    return updates


def build_similarity_clusters(notes: list[ExistingNote], min_score: int) -> list[list[ExistingNote]]:
    neighbors: defaultdict[str, set[str]] = defaultdict(set)
    note_lookup = {note.rel_path: note for note in notes}
    for left_index, left in enumerate(notes):
        for right in notes[left_index + 1 :]:
            score, _ = score_note_pair(left, right)
            if score < min_score:
                continue
            neighbors[left.rel_path].add(right.rel_path)
            neighbors[right.rel_path].add(left.rel_path)

    visited: set[str] = set()
    clusters: list[list[ExistingNote]] = []
    for rel_path in note_lookup:
        if rel_path in visited or rel_path not in neighbors:
            continue
        queue = [rel_path]
        component: list[ExistingNote] = []
        while queue:
            current = queue.pop()
            if current in visited:
                continue
            visited.add(current)
            component.append(note_lookup[current])
            queue.extend(neighbors[current] - visited)
        if len(component) >= 2:
            clusters.append(sorted(component, key=lambda item: item.rel_path))
    return clusters


def folder_clusters(notes: list[ExistingNote]) -> list[list[ExistingNote]]:
    groups: defaultdict[str, list[ExistingNote]] = defaultdict(list)
    for note in notes:
        if head_tool.normalize_text(note.folder) in SPECIAL_THEME_TITLES:
            groups[note.folder].append(note)
    return [sorted(items, key=lambda item: item.rel_path) for items in groups.values() if len(items) >= 2]


def dedupe_clusters(clusters: list[list[ExistingNote]]) -> list[list[ExistingNote]]:
    seen: set[tuple[str, ...]] = set()
    result: list[list[ExistingNote]] = []
    for cluster in clusters:
        key = tuple(sorted(note.rel_path for note in cluster))
        if key in seen:
            continue
        seen.add(key)
        result.append(cluster)
    return result


def pick_theme_title(cluster: list[ExistingNote]) -> str:
    title_signature_counts: Counter[str] = Counter()
    title_form_counts: defaultdict[str, Counter[str]] = defaultdict(Counter)
    signature_counts: Counter[str] = Counter()
    form_counts: defaultdict[str, Counter[str]] = defaultdict(Counter)
    for note in cluster:
        for signature in note.title_signatures:
            title_signature_counts[signature] += 1
        for token in note.title_tokens:
            title_form_counts[signal_router.token_signature(token)][token] += 1
        for signature in note.all_signatures:
            signature_counts[signature] += 1
        for signature, form in note.signature_forms.items():
            form_counts[signature][form] += 1

    repeated_titles = [signature for signature, count in title_signature_counts.most_common() if count >= 2]
    if repeated_titles:
        form = title_form_counts[repeated_titles[0]].most_common(1)[0][0]
        return signal_router.safe_note_title(form.title(), fallback="Theme")

    repeated = [signature for signature, count in signature_counts.most_common() if count >= 2]
    if repeated:
        words: list[str] = []
        for signature in repeated[:2]:
            form = form_counts[signature].most_common(1)[0][0]
            words.append(form)
        title = " ".join(words).strip()
        if title:
            return signal_router.safe_note_title(title.title(), fallback="Theme")

    return signal_router.safe_note_title(cluster[0].title, fallback="Theme")


def theme_note_body(title: str, rel_paths: list[str], shared_tokens: list[str]) -> str:
    summary = "Этот theme hub собран автоматически по уже существующим заметкам."
    notes_block = "\n".join(f"- [[{Path(path).with_suffix('').as_posix()}]]" for path in rel_paths)
    token_block = ", ".join(shared_tokens) or "none"
    return (
        f"# {title}\n\n"
        "## Summary\n"
        f"{summary}\n\n"
        "## Notes\n"
        f"{notes_block}\n\n"
        "## Signals\n"
        f"- repeated_tokens: {token_block}\n\n"
        "## Related\n"
    )


def shared_theme_tokens(cluster: list[ExistingNote]) -> list[str]:
    shared_title_counts: Counter[str] = Counter()
    title_form_counts: defaultdict[str, Counter[str]] = defaultdict(Counter)
    shared_counts: Counter[str] = Counter()
    form_counts: defaultdict[str, Counter[str]] = defaultdict(Counter)
    for note in cluster:
        for signature in note.title_signatures:
            shared_title_counts[signature] += 1
        for token in note.title_tokens:
            title_form_counts[signal_router.token_signature(token)][token] += 1
        for signature in note.all_signatures:
            shared_counts[signature] += 1
        for signature, form in note.signature_forms.items():
            form_counts[signature][form] += 1
    shared_tokens = [
        title_form_counts[signature].most_common(1)[0][0]
        for signature, count in shared_title_counts.most_common()
        if count >= 2
    ][:4]
    if not shared_tokens:
        shared_tokens = [
            form_counts[signature].most_common(1)[0][0]
            for signature, count in shared_counts.most_common()
            if count >= 2
        ][:4]
    return shared_tokens


def upsert_theme_cluster(
    vault: Path,
    cluster: list[ExistingNote],
    *,
    title: str,
    config: OrganizerConfig,
    memory_path: Path,
    obsidian_tool: Any,
) -> dict[str, Any]:
    rel_paths = [note.rel_path for note in cluster]
    path = obsidian_tool.build_note_path(vault, title, None, config.theme_directory)
    now = datetime.now(ZoneInfo(config.timezone_name))
    shared_tokens = shared_theme_tokens(cluster)

    if not path.exists():
        frontmatter = signal_router.render_frontmatter(
            {
                "title": title,
                "note_kind": "theme",
                "source": "existing-notes-organizer",
                "mentions_count": str(len(cluster)),
                "updated_at": now.isoformat(),
            }
        )
        signal_router.write_text(path, frontmatter + "\n" + theme_note_body(title, rel_paths, shared_tokens))
    else:
        current = signal_router.read_text(path)
        updated = signal_router.merge_frontmatter(
            current,
            {
                "title": title,
                "note_kind": "theme",
                "source": "existing-notes-organizer",
                "mentions_count": str(len(cluster)),
                "updated_at": now.isoformat(),
            },
            obsidian_tool,
        )
        signal_router.write_text(path, updated)

    index = obsidian_tool.build_index(vault)
    theme_note = obsidian_tool.resolve_note(index, path.relative_to(vault).as_posix())
    target_notes = [obsidian_tool.resolve_note(index, rel_path) for rel_path in rel_paths]
    theme_update = obsidian_tool.update_note_with_links(theme_note, target_notes, index.stem_counts, "Related", dry_run=False)
    backlink_changes = []
    for target_note in target_notes:
        backlink_changes.append(
            obsidian_tool.update_note_with_links(target_note, [theme_note], index.stem_counts, "Related", dry_run=False)
        )

    signal_router.upsert_registry_entry(
        memory_path,
        section_name="Themes Registry",
        prefix="theme",
        key_field="theme",
        key_value=title,
        fields={
            "theme": title,
            "mentions_count": str(len(cluster)),
            "related_notes": ", ".join(rel_paths),
            "trend": "organized",
            "importance_estimate": "medium",
        },
    )
    return {
        "title": title,
        "path": path.relative_to(vault).as_posix(),
        "note_count": len(cluster),
        "notes": rel_paths,
        "shared_tokens": shared_tokens,
        "theme_changed": theme_update["changed"],
        "backlinks_changed": sum(1 for item in backlink_changes if item["changed"]),
    }


def create_or_update_theme_notes(
    vault: Path,
    clusters: list[list[ExistingNote]],
    config: OrganizerConfig,
    memory_path: Path,
    obsidian_tool: Any,
) -> list[dict[str, Any]]:
    return [
        upsert_theme_cluster(
            vault,
            cluster,
            title=pick_theme_title(cluster),
            config=config,
            memory_path=memory_path,
            obsidian_tool=obsidian_tool,
        )
        for cluster in clusters
    ]


def create_or_update_folder_themes(
    vault: Path,
    notes: list[ExistingNote],
    config: OrganizerConfig,
    memory_path: Path,
    obsidian_tool: Any,
) -> list[dict[str, Any]]:
    groups: defaultdict[str, list[ExistingNote]] = defaultdict(list)
    for note in notes:
        normalized_folder = head_tool.normalize_text(note.folder)
        if normalized_folder in SPECIAL_THEME_TITLES:
            groups[normalized_folder].append(note)
    results: list[dict[str, Any]] = []
    for normalized_folder, cluster in groups.items():
        if len(cluster) < 2:
            continue
        results.append(
            upsert_theme_cluster(
                vault,
                sorted(cluster, key=lambda item: item.rel_path),
                title=SPECIAL_THEME_TITLES[normalized_folder],
                config=config,
                memory_path=memory_path,
                obsidian_tool=obsidian_tool,
            )
        )
    return results


def cleanup_candidates(vault: Path, config: OrganizerConfig, obsidian_tool: Any) -> list[dict[str, Any]]:
    index = obsidian_tool.build_index(vault)
    candidates: list[dict[str, Any]] = []
    for note in index.notes:
        rel_path = note.rel_path
        if rel_path == "Memory.md":
            continue
        if starts_with_any(rel_path, config.cleanup_prefixes):
            text = signal_router.read_text(note.path)
            _, body = obsidian_tool.split_frontmatter(text)
            word_count = len(body.split())
            title_norm = head_tool.normalize_text(note.title)
            low_signal = word_count < config.cleanup_min_words or any(token in title_norm for token in CLEANUP_TITLE_HINTS)
            if low_signal:
                candidates.append(
                    {
                        "title": note.title,
                        "path": rel_path,
                        "reason": "low-signal voice capture",
                        "classification": "review-or-archive",
                    }
                )
            continue
        if "/" not in rel_path and rel_path.endswith(".md"):
            candidates.append(
                {
                    "title": note.title,
                    "path": rel_path,
                    "reason": "root-level loose note needs review",
                    "classification": "clarify-or-move",
                }
            )
    return candidates


def write_cleanup_registry(memory_path: Path, candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    written: list[dict[str, Any]] = []
    for item in candidates:
        signal_router.upsert_registry_entry(
            memory_path,
            section_name="Cleanup Registry",
            prefix="cleanup",
            key_field="title",
            key_value=item["title"],
            fields={
                "title": item["title"],
                "classification": item["classification"],
                "reason": item["reason"],
                "confidence": "medium",
                "suggested_action": str(item.get("suggested_action") or "review and either archive, move, or rewrite"),
                "confirmation_required": str(item.get("confirmation_required") or "yes"),
                "resolved_state": str(item.get("resolved_state") or "open"),
            },
        )
        written.append(item)
    return written


def organize_existing_notes(vault: Path, config: OrganizerConfig, memory_path: Path | None = None) -> dict[str, Any]:
    obsidian_tool = signal_router.load_obsidian_tool_module()
    resolved_memory = memory_path or vault / "Memory.md"
    if not resolved_memory.exists():
        signal_router.write_text(resolved_memory, head_tool.default_memory_template())

    staged_notes = stage_root_notes(vault, config, obsidian_tool)
    notes = build_existing_notes(vault, config, obsidian_tool)
    normalized_notes = [note.rel_path for note in notes if ensure_note_shell(note)]
    related_updates = connect_related_notes(vault, notes, config, obsidian_tool)
    similarity_clusters = build_similarity_clusters(notes, config.min_theme_score)
    specific_clusters = dedupe_clusters(similarity_clusters)
    theme_updates = [
        *create_or_update_theme_notes(vault, specific_clusters, config, resolved_memory, obsidian_tool),
        *create_or_update_folder_themes(vault, notes, config, resolved_memory, obsidian_tool),
    ]
    cleanup_updates = write_cleanup_registry(
        resolved_memory,
        [*cleanup_candidates(vault, config, obsidian_tool), *staged_notes],
    )
    now = datetime.now(ZoneInfo(config.timezone_name))
    signal_router.append_change_log(
        resolved_memory,
        f"{now:%Y-%m-%d}: organized existing notes, refreshed related links, and updated theme hubs.",
    )
    return {
        "notes_considered": len(notes),
        "related_links": related_updates,
        "normalized_notes": normalized_notes,
        "staged_notes": staged_notes,
        "themes": theme_updates,
        "cleanup_candidates": cleanup_updates,
        "memory_path": resolved_memory.as_posix(),
    }


def command_organize(args: argparse.Namespace) -> int:
    vault = Path(args.vault).expanduser().resolve()
    if not vault.exists() or not vault.is_dir():
        raise OrganizerError(f"Vault does not exist: {vault}")
    memory_path = Path(args.memory_path).expanduser().resolve() if args.memory_path else None
    config = build_config(args)
    payload = organize_existing_notes(vault, config, memory_path=memory_path)
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Organize existing Obsidian notes into better links and theme hubs.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    organize = subparsers.add_parser("organize", help="Connect existing notes and build theme hubs.")
    organize.add_argument("vault", help="Path to the Obsidian vault")
    organize.add_argument("--memory-path", help="Optional path to Memory.md")
    organize.add_argument("--include", action="append", help="Comma-separated include prefixes. Defaults to Идеи, Мысли, посты, Мой путь.")
    organize.add_argument("--exclude", action="append", help="Comma-separated exclude prefixes.")
    organize.add_argument("--cleanup", action="append", help="Comma-separated cleanup prefixes.")
    organize.add_argument("--theme-dir", default="Темы", help="Directory for generated theme notes.")
    organize.add_argument("--distribution-dir", default=DEFAULT_DISTRIBUTION_DIR, help="Directory for staged loose notes.")
    organize.add_argument("--timezone", default="Asia/Bangkok", help="Timezone for timestamps.")
    organize.add_argument("--max-related", type=int, default=3, help="Maximum related-note edges per note.")
    organize.add_argument("--min-link-score", type=int, default=10, help="Minimum similarity score to add direct related links.")
    organize.add_argument("--min-theme-score", type=int, default=10, help="Minimum similarity score to cluster notes into themes.")
    organize.add_argument("--cleanup-min-words", type=int, default=12, help="Word threshold for low-signal cleanup candidates.")
    organize.set_defaults(func=command_organize)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except OrganizerError as exc:
        parser.exit(status=1, message=f"{exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
