#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys
from collections import Counter
from itertools import combinations
from pathlib import Path
from typing import Any

import obsidian_head_tool as head_tool


class GraphToolError(Exception):
    pass


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
    raise GraphToolError("Could not find obsidian-vault-manager script. Set OBSIDIAN_TOOL_PATH if needed.")


def should_exclude(rel_path: str, exclude_prefixes: list[str]) -> bool:
    normalized = head_tool.normalize_path(rel_path)
    for prefix in exclude_prefixes:
        normalized_prefix = head_tool.normalize_path(prefix)
        if not normalized_prefix:
            continue
        if normalized == normalized_prefix or normalized.startswith(normalized_prefix + "/"):
            return True
    return False


def build_graph_summary(vault: Path, *, limit: int = 10, exclude_prefixes: list[str] | None = None) -> dict[str, Any]:
    notes = head_tool.build_notes(vault)
    prefixes = exclude_prefixes or []
    filtered_notes = [note for note in notes if not should_exclude(note.rel_path, prefixes)]
    text_lookup, path_lookup = head_tool.build_lookup(filtered_notes)

    inbound_counts: Counter[str] = Counter()
    unresolved_links: Counter[str] = Counter()
    total_links = 0

    for note in filtered_notes:
        for raw_target in note.outbound_links:
            total_links += 1
            target = head_tool.resolve_target(raw_target, text_lookup, path_lookup)
            if target is None:
                unresolved_links[raw_target] += 1
                continue
            inbound_counts[target.rel_path] += 1

    hubs = sorted(
        filtered_notes,
        key=lambda note: (inbound_counts[note.rel_path] + len(note.outbound_links), inbound_counts[note.rel_path], len(note.outbound_links), note.title),
        reverse=True,
    )[:limit]
    orphans = [
        note
        for note in sorted(filtered_notes, key=lambda note: note.title.casefold())
        if inbound_counts[note.rel_path] == 0 and len(note.outbound_links) == 0
    ][:limit]
    low_link_notes = [
        note
        for note in sorted(filtered_notes, key=lambda note: (inbound_counts[note.rel_path] + len(note.outbound_links), note.title.casefold()))
        if inbound_counts[note.rel_path] + len(note.outbound_links) <= 1
    ][:limit]

    return {
        "totals": {
            "notes": len(filtered_notes),
            "links": total_links,
            "resolved_links": total_links - sum(unresolved_links.values()),
            "unresolved_links": sum(unresolved_links.values()),
            "orphan_notes": len([note for note in filtered_notes if inbound_counts[note.rel_path] == 0 and len(note.outbound_links) == 0]),
        },
        "hubs": [
            {
                "title": note.title,
                "path": note.rel_path,
                "inbound_links": inbound_counts[note.rel_path],
                "outbound_links": len(note.outbound_links),
                "connectivity": inbound_counts[note.rel_path] + len(note.outbound_links),
            }
            for note in hubs
        ],
        "orphans": [
            {"title": note.title, "path": note.rel_path}
            for note in orphans
        ],
        "low_link_notes": [
            {
                "title": note.title,
                "path": note.rel_path,
                "inbound_links": inbound_counts[note.rel_path],
                "outbound_links": len(note.outbound_links),
            }
            for note in low_link_notes
        ],
        "unresolved_links": [
            {"target": target, "count": count}
            for target, count in unresolved_links.most_common(limit)
        ],
    }


def build_link_suggestions(vault: Path, *, limit: int = 10, min_score: int = 2, exclude_prefixes: list[str] | None = None) -> list[dict[str, Any]]:
    notes = head_tool.build_notes(vault)
    prefixes = exclude_prefixes or []
    filtered_notes = [note for note in notes if not should_exclude(note.rel_path, prefixes)]
    text_lookup, path_lookup = head_tool.build_lookup(filtered_notes)

    existing_edges: set[tuple[str, str]] = set()
    for note in filtered_notes:
        for raw_target in note.outbound_links:
            target = head_tool.resolve_target(raw_target, text_lookup, path_lookup)
            if target is None:
                continue
            existing_edges.add((note.rel_path, target.rel_path))

    suggestions: list[dict[str, Any]] = []
    for left, right in combinations(filtered_notes, 2):
        if (left.rel_path, right.rel_path) in existing_edges or (right.rel_path, left.rel_path) in existing_edges:
            continue
        left_tags = {head_tool.normalize_text(tag) for tag in left.tags}
        right_tags = {head_tool.normalize_text(tag) for tag in right.tags}
        shared_tags = sorted(tag for tag in left_tags & right_tags if tag)
        left_tokens = set(head_tool.title_tokens(left.title))
        right_tokens = set(head_tool.title_tokens(right.title))
        shared_tokens = sorted(token for token in left_tokens & right_tokens if token)
        score = len(shared_tags) * 2 + len(shared_tokens)
        if score < min_score:
            continue
        suggestions.append(
            {
                "source": left.rel_path,
                "target": right.rel_path,
                "score": score,
                "shared_tags": shared_tags,
                "shared_title_tokens": shared_tokens,
            }
        )

    suggestions.sort(key=lambda item: (item["score"], item["source"], item["target"]), reverse=True)
    return suggestions[:limit]


def connect_notes_in_vault(
    vault: Path,
    *,
    source: str,
    targets: list[str],
    section: str = "Related",
    bidirectional: bool = True,
    create_missing: bool = False,
    new_note_dir: str | None = None,
    dry_run: bool = False,
) -> dict[str, Any]:
    obsidian_tool = load_obsidian_tool_module()
    index = obsidian_tool.build_index(vault)
    source_note = obsidian_tool.resolve_note(index, source)
    target_notes, created_targets = obsidian_tool.resolve_targets(
        vault=vault,
        index=index,
        target_queries=targets,
        create_missing=create_missing,
        new_note_dir=new_note_dir,
        dry_run=dry_run,
    )
    target_notes = [target for target in target_notes if target.path != source_note.path]
    updates = [
        obsidian_tool.update_note_with_links(
            note=source_note,
            target_notes=target_notes,
            stem_counts=index.stem_counts,
            section_name=section,
            dry_run=dry_run,
        )
    ]
    if bidirectional:
        for target in target_notes:
            updates.append(
                obsidian_tool.update_note_with_links(
                    note=target,
                    target_notes=[source_note],
                    stem_counts=index.stem_counts,
                    section_name=section,
                    dry_run=dry_run,
                )
            )
    return {
        "source": source_note.rel_path,
        "targets": [target.rel_path for target in target_notes],
        "created_targets": created_targets,
        "updates": updates,
        "dry_run": dry_run,
    }


def format_graph_summary(summary: dict[str, Any]) -> str:
    totals = summary["totals"]
    hubs = ", ".join(item["title"] for item in summary["hubs"][:3]) or "none"
    orphans = ", ".join(item["title"] for item in summary["orphans"][:3]) or "none"
    unresolved = ", ".join(item["target"] for item in summary["unresolved_links"][:3]) or "none"
    return (
        "Graph summary\n"
        f"- notes: {totals['notes']}\n"
        f"- links: {totals['links']}\n"
        f"- orphan notes: {totals['orphan_notes']}\n"
        f"- hubs: {hubs}\n"
        f"- unresolved links: {unresolved}\n"
        f"- low-link notes: {', '.join(item['title'] for item in summary['low_link_notes'][:3]) or 'none'}"
    )


def parse_exclude_prefixes(values: list[str] | None) -> list[str]:
    if not values:
        return []
    items: list[str] = []
    for raw in values:
        for part in raw.split(","):
            cleaned = part.strip()
            if cleaned:
                items.append(cleaned)
    return items


def emit(payload: Any, as_json: bool) -> None:
    if as_json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return
    if isinstance(payload, dict):
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return
    if isinstance(payload, list):
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return
    print(payload)


def command_graph_stats(args: argparse.Namespace) -> int:
    vault = head_tool.ensure_vault(args.vault)
    summary = build_graph_summary(
        vault,
        limit=args.limit,
        exclude_prefixes=parse_exclude_prefixes(args.exclude),
    )
    if args.json:
        emit(summary, as_json=True)
    else:
        print(format_graph_summary(summary))
    return 0


def command_suggest_links(args: argparse.Namespace) -> int:
    vault = head_tool.ensure_vault(args.vault)
    suggestions = build_link_suggestions(
        vault,
        limit=args.limit,
        min_score=args.min_score,
        exclude_prefixes=parse_exclude_prefixes(args.exclude),
    )
    emit(suggestions, as_json=True)
    return 0


def command_connect_note(args: argparse.Namespace) -> int:
    vault = head_tool.ensure_vault(args.vault)
    payload = connect_notes_in_vault(
        vault,
        source=args.source,
        targets=parse_exclude_prefixes(args.targets),
        section=args.section,
        bidirectional=not args.one_way,
        create_missing=args.create_missing,
        new_note_dir=args.new_note_dir,
        dry_run=args.dry_run,
    )
    emit(payload, as_json=True)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Graph and linking utilities for an Obsidian vault.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    stats_parser = subparsers.add_parser("graph-stats", help="Summarize vault graph connectivity.")
    stats_parser.add_argument("vault", help="Path to the Obsidian vault.")
    stats_parser.add_argument("--limit", type=int, default=10, help="Maximum items per section.")
    stats_parser.add_argument("--exclude", action="append", help="Comma-separated relative paths or prefixes to exclude.")
    stats_parser.add_argument("--json", action="store_true", help="Emit JSON.")
    stats_parser.set_defaults(func=command_graph_stats)

    suggest_parser = subparsers.add_parser("suggest-links", help="Suggest high-value note links.")
    suggest_parser.add_argument("vault", help="Path to the Obsidian vault.")
    suggest_parser.add_argument("--limit", type=int, default=10, help="Maximum number of suggestions.")
    suggest_parser.add_argument("--min-score", type=int, default=2, help="Minimum overlap score to include.")
    suggest_parser.add_argument("--exclude", action="append", help="Comma-separated relative paths or prefixes to exclude.")
    suggest_parser.set_defaults(func=command_suggest_links)

    connect_parser = subparsers.add_parser("connect-note", help="Create missing wiki-links between notes.")
    connect_parser.add_argument("vault", help="Path to the Obsidian vault.")
    connect_parser.add_argument("--source", required=True, help="Source note title, alias, stem, or relative path.")
    connect_parser.add_argument("--targets", action="append", required=True, help="Comma-separated target notes. Repeatable.")
    connect_parser.add_argument("--section", default="Related", help="Section name for inserted links.")
    connect_parser.add_argument("--one-way", action="store_true", help="Only add links on the source note.")
    connect_parser.add_argument("--create-missing", action="store_true", help="Create target notes if they do not exist.")
    connect_parser.add_argument("--new-note-dir", help="Folder for notes created via --create-missing.")
    connect_parser.add_argument("--dry-run", action="store_true", help="Preview changes without writing files.")
    connect_parser.set_defaults(func=command_connect_note)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except GraphToolError as exc:
        parser.exit(status=1, message=f"{exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
