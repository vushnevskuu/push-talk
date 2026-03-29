#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import subprocess
import tempfile
from collections import Counter
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import obsidian_graph_tool as graph_tool
import obsidian_head_tool as head_tool

WIDTH = 1440
HEIGHT = 1600
PADDING = 64
REPORTS_DIR = "Reports/Infographics"
TRACKING_DIRECTORY = "Logs/Tracking"

PALETTE = {
    "bg": "#F5F2EB",
    "panel": "#FCFAF6",
    "border": "#D9D2C7",
    "line": "#E7E0D5",
    "text": "#141414",
    "muted": "#6B6B6B",
    "soft": "#9A9489",
    "track": "#E8E2D8",
    "dark": "#141414",
    "mid": "#4C4C4C",
    "light": "#8A8A8A",
    "pale": "#BCB4A8",
}

TRACKING_FILES = {
    "skill": "skills",
    "workout": "workouts",
    "nutrition": "nutrition",
    "body": "body",
}

MODE_ALIASES = {
    "overview": {"overview", "vault", "summary", "обзор", "общая", "общий"},
    "graph": {"graph", "mindmap", "mind map", "map", "граф", "карта", "связи"},
    "health": {"health", "fitness", "wellness", "здоровье", "фитнес"},
    "skills": {"skills", "skillboard", "skill-board", "навыки", "скиллы", "скилы"},
    "workout": {"workout", "gym", "training", "зал", "тренировка", "тренировки"},
    "nutrition": {"nutrition", "food", "diet", "еда", "питание", "nutrition-log"},
    "body": {"body", "recovery", "weight", "sleep", "тело", "вес", "сон"},
}

SKILL_PREFIXES = (
    "skill:",
    "skill ",
    "навык:",
    "навык ",
    "скилл:",
    "скилл ",
    "скил:",
    "скил ",
)


def svg_escape(value: Any) -> str:
    return html.escape(str(value), quote=False)


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.casefold()).strip()


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.casefold())
    slug = slug.strip("-")
    return slug or "report"


def truncate(value: str, limit: int) -> str:
    if len(value) <= limit:
        return value
    return value[: max(0, limit - 1)].rstrip() + "..."


def format_int(value: float | int) -> str:
    return f"{int(round(value)):,}".replace(",", " ")


def format_decimal(value: float | int | None, suffix: str = "") -> str:
    if value is None:
        return "-"
    if abs(float(value) - round(float(value))) < 0.05:
        return f"{int(round(float(value)))}{suffix}"
    return f"{float(value):.1f}{suffix}"


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def safe_ratio(value: float, total: float) -> float:
    if total <= 0:
        return 0.0
    return clamp(value / total, 0.0, 1.0)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def tracking_root(vault: Path) -> Path:
    return vault / TRACKING_DIRECTORY


def parse_tracking_entries(vault: Path) -> list[dict[str, Any]]:
    root = tracking_root(vault)
    if not root.exists():
        return []

    entries: list[dict[str, Any]] = []
    for path in sorted(root.glob("*.md")):
        current: dict[str, Any] | None = None
        for line in read_text(path).splitlines():
            stripped = line.strip()
            if stripped.startswith("## "):
                if current:
                    current["source_path"] = path.relative_to(vault).as_posix()
                    entries.append(current)
                current = {"heading": stripped[3:].strip()}
                continue
            if current is None or not stripped.startswith("- ") or ":" not in stripped:
                continue
            key, value = stripped[2:].split(":", 1)
            current[key.strip()] = value.strip()
        if current:
            current["source_path"] = path.relative_to(vault).as_posix()
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
        return parsed.replace(tzinfo=ZoneInfo(timezone_name))
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=ZoneInfo(timezone_name))
    return parsed


def parse_entry_number(entry: dict[str, Any], key: str) -> float | None:
    raw = entry.get(key)
    if raw in (None, ""):
        return None
    try:
        return float(str(raw).replace(",", "."))
    except ValueError:
        return None


def describe_entry(entry: dict[str, Any] | None, fallback: str) -> str:
    if not entry:
        return fallback
    return str(entry.get("summary") or entry.get("raw_text") or entry.get("heading") or fallback)


def sort_entries(entries: list[dict[str, Any]], timezone_name: str) -> list[dict[str, Any]]:
    return sorted(
        entries,
        key=lambda item: parse_entry_datetime(item, timezone_name) or datetime.min.replace(tzinfo=ZoneInfo(timezone_name)),
        reverse=True,
    )


def recent_lines(entries: list[dict[str, Any]], timezone_name: str, limit: int = 5) -> list[str]:
    rows: list[str] = []
    for entry in sort_entries(entries, timezone_name)[:limit]:
        entry_dt = parse_entry_datetime(entry, timezone_name)
        prefix = entry_dt.astimezone(ZoneInfo(timezone_name)).strftime("%d %b") if entry_dt else "log"
        rows.append(f"{prefix}  {truncate(describe_entry(entry, 'entry'), 54)}")
    return rows


def daily_activity(entries: list[dict[str, Any]], timezone_name: str, days: int = 7) -> list[tuple[str, int]]:
    zone = ZoneInfo(timezone_name)
    today = datetime.now(zone).date()
    start = today - timedelta(days=days - 1)
    counts: dict[date, int] = {start + timedelta(days=index): 0 for index in range(days)}
    for entry in entries:
        entry_dt = parse_entry_datetime(entry, timezone_name)
        if entry_dt is None:
            continue
        local_date = entry_dt.astimezone(zone).date()
        if local_date in counts:
            counts[local_date] += 1
    return [(day.strftime("%d %b"), counts[day]) for day in sorted(counts)]


def entries_for_category(entries: list[dict[str, Any]], category: str) -> list[dict[str, Any]]:
    normalized = normalize_text(category)
    return [entry for entry in entries if normalize_text(str(entry.get("category") or "")) == normalized]


def build_tracking_summary(vault: Path, timezone_name: str) -> dict[str, Any]:
    entries = parse_tracking_entries(vault)
    total_xp = 0
    skill_xp: Counter[str] = Counter()
    category_counts: Counter[str] = Counter()
    latest_workout: dict[str, Any] | None = None
    latest_workout_dt: datetime | None = None
    latest_nutrition: dict[str, Any] | None = None
    latest_nutrition_dt: datetime | None = None
    latest_body: dict[str, Any] | None = None
    latest_body_dt: datetime | None = None
    workout_count_week = 0
    today_calories = 0.0
    today_protein = 0.0
    now_local = datetime.now(ZoneInfo(timezone_name))
    current_date = now_local.date()
    current_week = now_local.isocalendar()[:2]

    for entry in entries:
        xp = int(parse_entry_number(entry, "xp") or 0)
        total_xp += xp
        category = str(entry.get("category") or "").strip()
        if category:
            category_counts[category] += 1
        skill_name = str(entry.get("skill") or "").strip()
        if skill_name:
            skill_xp[skill_name] += xp

        entry_dt = parse_entry_datetime(entry, timezone_name)
        if category == "workout":
            if latest_workout is None or (entry_dt is not None and (latest_workout_dt is None or entry_dt > latest_workout_dt)):
                latest_workout = entry
                latest_workout_dt = entry_dt
            if entry_dt and entry_dt.astimezone(ZoneInfo(timezone_name)).isocalendar()[:2] == current_week:
                workout_count_week += 1
        elif category == "nutrition":
            if latest_nutrition is None or (entry_dt is not None and (latest_nutrition_dt is None or entry_dt > latest_nutrition_dt)):
                latest_nutrition = entry
                latest_nutrition_dt = entry_dt
            if entry_dt and entry_dt.astimezone(ZoneInfo(timezone_name)).date() == current_date:
                today_calories += parse_entry_number(entry, "calories") or 0.0
                today_protein += parse_entry_number(entry, "protein_g") or 0.0
        elif category == "body":
            if latest_body is None or (entry_dt is not None and (latest_body_dt is None or entry_dt > latest_body_dt)):
                latest_body = entry
                latest_body_dt = entry_dt

    current_level = 1 + (total_xp // 100)
    return {
        "entries": entries,
        "entry_count": len(entries),
        "category_counts": dict(category_counts),
        "tracked_skill_count": len(skill_xp),
        "total_xp": total_xp,
        "level": current_level,
        "xp_into_level": total_xp % 100,
        "xp_to_next": 100 - (total_xp % 100) if total_xp % 100 else 100,
        "top_skills": skill_xp.most_common(8),
        "latest_workout": latest_workout,
        "latest_nutrition": latest_nutrition,
        "latest_body": latest_body,
        "today_calories": int(round(today_calories)),
        "today_protein": int(round(today_protein)),
        "workouts_this_week": workout_count_week,
    }


def suggest_focus(summary: dict[str, Any]) -> str:
    for key in ("project_candidates", "dormant_candidates", "idea_candidates", "cleanup_candidates"):
        items = summary.get(key, [])
        if items:
            return items[0]["title"]
    return "Capture one useful idea and connect it to the graph."


def target_segments(value: float, target: float) -> list[tuple[float, str]]:
    filled = clamp(value, 0.0, target)
    remainder = max(0.0, target - filled)
    return [
        (safe_ratio(filled, target), PALETTE["dark"]),
        (safe_ratio(remainder, target), PALETTE["pale"]),
    ]


def share_segments(primary: float, secondary: float) -> list[tuple[float, str]]:
    total = max(1.0, primary + secondary)
    return [
        (safe_ratio(primary, total), PALETTE["dark"]),
        (safe_ratio(secondary, total), PALETTE["light"]),
    ]


def donut_chart(cx: float, cy: float, radius: float, thickness: float, segments: list[tuple[float, str]]) -> str:
    circumference = 2 * 3.141592653589793 * radius
    output = [
        f'<circle cx="{cx}" cy="{cy}" r="{radius}" fill="none" stroke="{PALETTE["track"]}" stroke-width="{thickness}"/>'
    ]
    offset = 0.0
    for value, color in segments:
        fraction = clamp(value, 0.0, 1.0)
        if fraction <= 0:
            continue
        dash = circumference * fraction
        output.append(
            f'<circle cx="{cx}" cy="{cy}" r="{radius}" fill="none" stroke="{color}" stroke-width="{thickness}" '
            f'stroke-linecap="round" stroke-dasharray="{dash:.2f} {circumference:.2f}" stroke-dashoffset="{-offset:.2f}" '
            f'transform="rotate(-90 {cx} {cy})"/>'
        )
        offset += dash
    return "\n".join(output)


def panel_frame(x: float, y: float, w: float, h: float) -> str:
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="28" '
        f'fill="{PALETTE["panel"]}" stroke="{PALETTE["border"]}" stroke-width="2"/>'
    )


def stat_card(x: float, y: float, w: float, h: float, label: str, value: str, note: str) -> str:
    return f"""
    <g>
      {panel_frame(x, y, w, h)}
      <text x="{x+28}" y="{y+40}" font-family="'Avenir Next','SF Pro Display','Helvetica Neue',Arial,sans-serif" font-size="18" fill="{PALETTE['muted']}" letter-spacing="1.2">{svg_escape(label.upper())}</text>
      <text x="{x+28}" y="{y+102}" font-family="'Avenir Next','SF Pro Display','Helvetica Neue',Arial,sans-serif" font-size="54" font-weight="700" fill="{PALETTE['text']}">{svg_escape(value)}</text>
      <text x="{x+28}" y="{y+h-24}" font-family="'Avenir Next','SF Pro Text','Helvetica Neue',Arial,sans-serif" font-size="18" fill="{PALETTE['soft']}">{svg_escape(truncate(note, 42))}</text>
    </g>
    """


def donut_panel(x: float, y: float, w: float, h: float, panel: dict[str, Any]) -> str:
    legend_rows: list[str] = []
    legend_x = x + 304
    legend_y = y + 128
    for index, row in enumerate(panel.get("legend", [])[:4]):
        label, value, color = row
        line_y = legend_y + index * 54
        legend_rows.append(f'<rect x="{legend_x}" y="{line_y-10}" width="18" height="18" rx="5" fill="{color}"/>')
        legend_rows.append(
            f'<text x="{legend_x+30}" y="{line_y+4}" font-family="\'Avenir Next\',\'SF Pro Text\',\'Helvetica Neue\',Arial,sans-serif" font-size="20" fill="{PALETTE["text"]}">{svg_escape(truncate(str(label), 22))}</text>'
        )
        legend_rows.append(
            f'<text x="{x+w-28}" y="{line_y+4}" text-anchor="end" font-family="\'Avenir Next\',\'SF Pro Display\',\'Helvetica Neue\',Arial,sans-serif" font-size="20" font-weight="600" fill="{PALETTE["muted"]}">{svg_escape(str(value))}</text>'
        )

    return f"""
    <g>
      {panel_frame(x, y, w, h)}
      <text x="{x+28}" y="{y+44}" font-family="'Avenir Next','SF Pro Display','Helvetica Neue',Arial,sans-serif" font-size="28" font-weight="700" fill="{PALETTE['text']}">{svg_escape(panel['title'])}</text>
      <text x="{x+28}" y="{y+76}" font-family="'Avenir Next','SF Pro Text','Helvetica Neue',Arial,sans-serif" font-size="18" fill="{PALETTE['muted']}">{svg_escape(panel['subtitle'])}</text>
      {donut_chart(x+156, y+188, 86, 24, panel.get('segments', []))}
      <text x="{x+156}" y="{y+182}" text-anchor="middle" font-family="'Avenir Next','SF Pro Display','Helvetica Neue',Arial,sans-serif" font-size="42" font-weight="700" fill="{PALETTE['text']}">{svg_escape(panel['main_value'])}</text>
      <text x="{x+156}" y="{y+218}" text-anchor="middle" font-family="'Avenir Next','SF Pro Text','Helvetica Neue',Arial,sans-serif" font-size="18" fill="{PALETTE['muted']}">{svg_escape(panel['main_label'])}</text>
      {"".join(legend_rows)}
    </g>
    """


def bar_panel(x: float, y: float, w: float, h: float, panel: dict[str, Any]) -> str:
    items = panel.get("items", [])[:7]
    max_value = max((value for _, value in items), default=1)
    rows: list[str] = [
        panel_frame(x, y, w, h),
        f'<text x="{x+28}" y="{y+44}" font-family="\'Avenir Next\',\'SF Pro Display\',\'Helvetica Neue\',Arial,sans-serif" font-size="28" font-weight="700" fill="{PALETTE["text"]}">{svg_escape(panel["title"])}</text>',
        f'<text x="{x+28}" y="{y+76}" font-family="\'Avenir Next\',\'SF Pro Text\',\'Helvetica Neue\',Arial,sans-serif" font-size="18" fill="{PALETTE["muted"]}">{svg_escape(panel["subtitle"])}</text>',
    ]
    base_y = y + 136
    row_height = 72
    bar_x = x + 28
    bar_w = w - 56 - 130
    for index, (label, value) in enumerate(items):
        line_y = base_y + index * row_height
        fill_width = bar_w * (value / max_value if max_value else 0)
        rows.extend(
            [
                f'<text x="{bar_x}" y="{line_y}" font-family="\'Avenir Next\',\'SF Pro Text\',\'Helvetica Neue\',Arial,sans-serif" font-size="19" fill="{PALETTE["text"]}">{svg_escape(truncate(str(label), 30))}</text>',
                f'<rect x="{bar_x}" y="{line_y+14}" width="{bar_w}" height="14" rx="7" fill="{PALETTE["track"]}"/>',
                f'<rect x="{bar_x}" y="{line_y+14}" width="{fill_width:.2f}" height="14" rx="7" fill="{PALETTE["dark"]}"/>',
                f'<text x="{x+w-28}" y="{line_y+26}" text-anchor="end" font-family="\'Avenir Next\',\'SF Pro Display\',\'Helvetica Neue\',Arial,sans-serif" font-size="19" font-weight="600" fill="{PALETTE["muted"]}">{format_int(value)}</text>',
            ]
        )
    if not items:
        rows.append(
            f'<text x="{x+28}" y="{y+128}" font-family="\'Avenir Next\',\'SF Pro Text\',\'Helvetica Neue\',Arial,sans-serif" font-size="20" fill="{PALETTE["soft"]}">No data yet.</text>'
        )
    return "<g>" + "".join(rows) + "</g>"


def list_panel(x: float, y: float, w: float, h: float, panel: dict[str, Any]) -> str:
    rows: list[str] = [
        panel_frame(x, y, w, h),
        f'<text x="{x+28}" y="{y+44}" font-family="\'Avenir Next\',\'SF Pro Display\',\'Helvetica Neue\',Arial,sans-serif" font-size="28" font-weight="700" fill="{PALETTE["text"]}">{svg_escape(panel["title"])}</text>',
    ]
    subtitle = str(panel.get("subtitle") or "").strip()
    if subtitle:
        rows.append(
            f'<text x="{x+28}" y="{y+76}" font-family="\'Avenir Next\',\'SF Pro Text\',\'Helvetica Neue\',Arial,sans-serif" font-size="18" fill="{PALETTE["muted"]}">{svg_escape(subtitle)}</text>'
        )
    items = panel.get("items", [])[:8]
    base_y = y + (116 if subtitle else 96)
    for index, item in enumerate(items):
        line_y = base_y + index * 40
        rows.append(f'<rect x="{x+28}" y="{line_y-14}" width="14" height="14" rx="4" fill="{PALETTE["dark"]}"/>')
        rows.append(
            f'<text x="{x+54}" y="{line_y}" font-family="\'Avenir Next\',\'SF Pro Text\',\'Helvetica Neue\',Arial,sans-serif" font-size="19" fill="{PALETTE["text"]}">{svg_escape(truncate(str(item), 42))}</text>'
        )
    if not items:
        rows.append(
            f'<text x="{x+28}" y="{base_y}" font-family="\'Avenir Next\',\'SF Pro Text\',\'Helvetica Neue\',Arial,sans-serif" font-size="20" fill="{PALETTE["soft"]}">Nothing to show yet.</text>'
        )
    return "<g>" + "".join(rows) + "</g>"


def render_report_svg(report: dict[str, Any]) -> str:
    inner_width = WIDTH - (2 * PADDING)
    gap = 24
    stat_width = (inner_width - 3 * gap) / 4
    stat_y = 174
    stat_height = 156
    donut_y = 362
    donut_width = (inner_width - gap) / 2
    donut_height = 326
    bottom_y = 720
    bottom_height = HEIGHT - bottom_y - PADDING
    bar_width = 784
    list_width = inner_width - bar_width - gap
    list_height = (bottom_height - gap) / 2

    cards = []
    for index, card in enumerate(report["stats"][:4]):
        card_x = PADDING + index * (stat_width + gap)
        cards.append(stat_card(card_x, stat_y, stat_width, stat_height, card["label"], card["value"], card["note"]))

    circles = []
    for index, panel in enumerate(report["circles"][:2]):
        panel_x = PADDING + index * (donut_width + gap)
        circles.append(donut_panel(panel_x, donut_y, donut_width, donut_height, panel))

    right_x = PADDING + bar_width + gap
    list_panels = []
    for index, panel in enumerate(report["lists"][:2]):
        panel_y = bottom_y + index * (list_height + gap)
        list_panels.append(list_panel(right_x, panel_y, list_width, list_height, panel))

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}" fill="none">
  <rect width="{WIDTH}" height="{HEIGHT}" fill="{PALETTE['bg']}"/>
  <path d="M {PADDING} 132 H {WIDTH-PADDING}" stroke="{PALETTE['line']}" stroke-width="2"/>
  <path d="M {PADDING} {HEIGHT-PADDING} H {WIDTH-PADDING}" stroke="{PALETTE['line']}" stroke-width="2"/>

  <text x="{PADDING}" y="74" font-family="'Avenir Next','SF Pro Display','Helvetica Neue',Arial,sans-serif" font-size="18" fill="{PALETTE['muted']}" letter-spacing="1.4">OBSIDIAN HEAD AGENT</text>
  <text x="{PADDING}" y="126" font-family="'Avenir Next','SF Pro Display','Helvetica Neue',Arial,sans-serif" font-size="58" font-weight="700" fill="{PALETTE['text']}">{svg_escape(report['title'])}</text>
  <text x="{PADDING}" y="154" font-family="'Avenir Next','SF Pro Text','Helvetica Neue',Arial,sans-serif" font-size="22" fill="{PALETTE['muted']}">{svg_escape(report['subtitle'])}</text>
  <text x="{WIDTH-PADDING}" y="74" text-anchor="end" font-family="'Avenir Next','SF Pro Text','Helvetica Neue',Arial,sans-serif" font-size="18" fill="{PALETTE['soft']}">minimal image report</text>

  {"".join(cards)}
  {"".join(circles)}
  {bar_panel(PADDING, bottom_y, bar_width, bottom_height, report['bar_panel'])}
  {"".join(list_panels)}

  <text x="{PADDING}" y="{HEIGHT-24}" font-family="'Avenir Next','SF Pro Text','Helvetica Neue',Arial,sans-serif" font-size="18" fill="{PALETTE['muted']}">{svg_escape(truncate(report['footer'], 110))}</text>
  <text x="{WIDTH-PADDING}" y="{HEIGHT-24}" text-anchor="end" font-family="'Avenir Next','SF Pro Text','Helvetica Neue',Arial,sans-serif" font-size="18" fill="{PALETTE['soft']}">{svg_escape(report['generated_at'])}</text>
</svg>
"""


def graph_excludes() -> list[str]:
    return ["Memory.md", "Inbox/Telegram", "Logs/Tracking", REPORTS_DIR]


def build_overview_report(vault: Path, timezone_name: str) -> dict[str, Any]:
    notes = head_tool.build_notes(vault)
    summary = head_tool.summarize_review(notes, days_stale=45, limit=8)
    graph = graph_tool.build_graph_summary(vault, limit=8, exclude_prefixes=graph_excludes())
    tracking = build_tracking_summary(vault, timezone_name)
    totals = summary["totals"]
    graph_totals = graph["totals"]
    connected = max(0, graph_totals["notes"] - graph_totals["orphan_notes"])
    focus_items = [suggest_focus(summary)]
    focus_items.extend(item["title"] for item in summary.get("dormant_candidates", [])[:3])

    return {
        "mode": "overview",
        "title": "Vault Overview",
        "subtitle": f"{vault.name}  {datetime.now(ZoneInfo(timezone_name)).strftime('%d %b %Y %H:%M')}",
        "generated_at": datetime.now(ZoneInfo(timezone_name)).strftime("%Y-%m-%d %H:%M"),
        "stats": [
            {"label": "Notes", "value": format_int(totals["notes"]), "note": f"{format_int(totals['words'])} words"},
            {"label": "Graph Links", "value": format_int(graph_totals["links"]), "note": f"{graph_totals['unresolved_links']} unresolved"},
            {"label": "Open Tasks", "value": format_int(totals["tasks_open"]), "note": f"{totals['tasks_done']} completed"},
            {"label": "Player XP", "value": format_int(tracking["total_xp"]), "note": f"level {tracking['level']}"},
        ],
        "circles": [
            {
                "title": "Task Balance",
                "subtitle": "Completed against open tasks across the vault.",
                "main_value": format_int(totals["tasks_done"]),
                "main_label": "done tasks",
                "segments": share_segments(totals["tasks_done"], totals["tasks_open"]),
                "legend": [
                    ("Done", format_int(totals["tasks_done"]), PALETTE["dark"]),
                    ("Open", format_int(totals["tasks_open"]), PALETTE["light"]),
                ],
            },
            {
                "title": "Graph Health",
                "subtitle": "Connected notes against isolated notes.",
                "main_value": format_int(connected),
                "main_label": "connected notes",
                "segments": share_segments(connected, graph_totals["orphan_notes"]),
                "legend": [
                    ("Connected", format_int(connected), PALETTE["dark"]),
                    ("Orphan", format_int(graph_totals["orphan_notes"]), PALETTE["light"]),
                ],
            },
        ],
        "bar_panel": {
            "title": "Theme Pressure",
            "subtitle": "Most repeated vault themes right now.",
            "items": [(item["theme"], item["count"]) for item in summary.get("themes", [])[:7]],
        },
        "lists": [
            {
                "title": "Top Hubs",
                "subtitle": "Most connected notes in the current graph.",
                "items": [item["title"] for item in graph.get("hubs", [])[:6]],
            },
            {
                "title": "Next Focus",
                "subtitle": "What deserves attention next.",
                "items": focus_items,
            },
        ],
        "footer": f"Current quest: {suggest_focus(summary)}",
    }


def build_graph_report(vault: Path, timezone_name: str) -> dict[str, Any]:
    graph = graph_tool.build_graph_summary(vault, limit=8, exclude_prefixes=graph_excludes())
    suggestions = graph_tool.build_link_suggestions(vault, limit=6, min_score=2, exclude_prefixes=graph_excludes())
    totals = graph["totals"]
    connected = max(0, totals["notes"] - totals["orphan_notes"])

    return {
        "mode": "graph",
        "title": "Graph Health",
        "subtitle": f"{vault.name}  connectivity snapshot",
        "generated_at": datetime.now(ZoneInfo(timezone_name)).strftime("%Y-%m-%d %H:%M"),
        "stats": [
            {"label": "Notes", "value": format_int(totals["notes"]), "note": "graph-scoped notes"},
            {"label": "Links", "value": format_int(totals["links"]), "note": f"{totals['resolved_links']} resolved"},
            {"label": "Orphans", "value": format_int(totals["orphan_notes"]), "note": "notes with no neighbors"},
            {"label": "Unresolved", "value": format_int(totals["unresolved_links"]), "note": "broken or ambiguous links"},
        ],
        "circles": [
            {
                "title": "Connectivity",
                "subtitle": "Connected notes versus orphan notes.",
                "main_value": format_int(connected),
                "main_label": "connected notes",
                "segments": share_segments(connected, totals["orphan_notes"]),
                "legend": [
                    ("Connected", format_int(connected), PALETTE["dark"]),
                    ("Orphan", format_int(totals["orphan_notes"]), PALETTE["light"]),
                ],
            },
            {
                "title": "Link Resolution",
                "subtitle": "Resolved links against unresolved targets.",
                "main_value": format_int(totals["resolved_links"]),
                "main_label": "resolved links",
                "segments": share_segments(totals["resolved_links"], totals["unresolved_links"]),
                "legend": [
                    ("Resolved", format_int(totals["resolved_links"]), PALETTE["dark"]),
                    ("Unresolved", format_int(totals["unresolved_links"]), PALETTE["light"]),
                ],
            },
        ],
        "bar_panel": {
            "title": "Hub Strength",
            "subtitle": "Notes with the strongest local connectivity.",
            "items": [(item["title"], item["connectivity"]) for item in graph.get("hubs", [])[:7]],
        },
        "lists": [
            {
                "title": "Low-Link Notes",
                "subtitle": "Candidates for linking or consolidation.",
                "items": [item["title"] for item in graph.get("low_link_notes", [])[:7]],
            },
            {
                "title": "Suggested Links",
                "subtitle": "High-overlap pairs worth connecting.",
                "items": [f"{Path(item['source']).stem}  {Path(item['target']).stem}" for item in suggestions[:7]],
            },
        ],
        "footer": "Use /link Source | Target to connect the best candidates.",
    }


def build_health_report(vault: Path, timezone_name: str) -> dict[str, Any]:
    tracking = build_tracking_summary(vault, timezone_name)
    entries = tracking["entries"]
    health_entries = [
        entry for entry in entries if str(entry.get("category") or "") in {"workout", "nutrition", "body"}
    ]
    latest_body = tracking["latest_body"] or {}
    latest_weight = parse_entry_number(latest_body, "weight_kg")
    latest_sleep = parse_entry_number(latest_body, "sleep_hours")
    recovery_value = latest_sleep if latest_sleep is not None else float(tracking["today_protein"])
    recovery_target = 8.0 if latest_sleep is not None else 160.0
    recovery_label = "sleep hours" if latest_sleep is not None else "protein today"
    recovery_note = "sleep against 8h target" if latest_sleep is not None else "protein against 160g target"

    return {
        "mode": "health",
        "title": "Health Snapshot",
        "subtitle": f"{vault.name}  training, nutrition, and recovery",
        "generated_at": datetime.now(ZoneInfo(timezone_name)).strftime("%Y-%m-%d %H:%M"),
        "stats": [
            {"label": "Workouts / Week", "value": format_int(tracking["workouts_this_week"]), "note": "current ISO week"},
            {"label": "Calories Today", "value": format_int(tracking["today_calories"]), "note": "nutrition logged today"},
            {"label": "Protein Today", "value": f"{format_int(tracking['today_protein'])}g", "note": "tracked intake"},
            {"label": "Latest Weight", "value": format_decimal(latest_weight, "kg"), "note": format_decimal(latest_sleep, "h") + " sleep"},
        ],
        "circles": [
            {
                "title": "Training Cadence",
                "subtitle": "Weekly workouts against a four-session target.",
                "main_value": format_int(tracking["workouts_this_week"]),
                "main_label": "sessions",
                "segments": target_segments(float(tracking["workouts_this_week"]), 4.0),
                "legend": [
                    ("Completed", format_int(tracking["workouts_this_week"]), PALETTE["dark"]),
                    ("Target", "4", PALETTE["light"]),
                ],
            },
            {
                "title": "Recovery Pulse",
                "subtitle": recovery_note,
                "main_value": format_decimal(recovery_value, "h" if latest_sleep is not None else "g"),
                "main_label": recovery_label,
                "segments": target_segments(float(recovery_value or 0.0), recovery_target),
                "legend": [
                    ("Current", format_decimal(recovery_value), PALETTE["dark"]),
                    ("Target", format_decimal(recovery_target), PALETTE["light"]),
                ],
            },
        ],
        "bar_panel": {
            "title": "Last 7 Days",
            "subtitle": "How often health-related logs were captured.",
            "items": daily_activity(health_entries, timezone_name, days=7),
        },
        "lists": [
            {
                "title": "Recent Workout / Body",
                "subtitle": "Latest training and body check-ins.",
                "items": recent_lines(entries_for_category(entries, "workout"), timezone_name, 3)
                + recent_lines(entries_for_category(entries, "body"), timezone_name, 3),
            },
            {
                "title": "Recent Nutrition",
                "subtitle": "Latest intake entries and current snapshot.",
                "items": recent_lines(entries_for_category(entries, "nutrition"), timezone_name, 6),
            },
        ],
        "footer": f"Latest workout: {describe_entry(tracking['latest_workout'], 'none')}",
    }


def build_skills_report(vault: Path, timezone_name: str) -> dict[str, Any]:
    tracking = build_tracking_summary(vault, timezone_name)
    entries = entries_for_category(tracking["entries"], "skill")
    top_skill_name, top_skill_xp = tracking["top_skills"][0] if tracking["top_skills"] else ("none", 0)
    recent_skill_lines = recent_lines(entries, timezone_name, 7)

    return {
        "mode": "skills",
        "title": "Skill Progression",
        "subtitle": f"{vault.name}  gamified growth across tracked skills",
        "generated_at": datetime.now(ZoneInfo(timezone_name)).strftime("%Y-%m-%d %H:%M"),
        "stats": [
            {"label": "Total XP", "value": format_int(tracking["total_xp"]), "note": "all tracked actions"},
            {"label": "Level", "value": format_int(tracking["level"]), "note": f"{tracking['xp_to_next']} xp to next"},
            {"label": "Skills Tracked", "value": format_int(tracking["tracked_skill_count"]), "note": "unique named skills"},
            {"label": "Top Skill", "value": truncate(top_skill_name, 14), "note": f"{top_skill_xp} xp"},
        ],
        "circles": [
            {
                "title": "Level Progress",
                "subtitle": "Progress inside the current player level.",
                "main_value": format_int(tracking["xp_into_level"]),
                "main_label": "xp in level",
                "segments": target_segments(float(tracking["xp_into_level"]), 100.0),
                "legend": [
                    ("Current", format_int(tracking["xp_into_level"]), PALETTE["dark"]),
                    ("Next level", "100", PALETTE["light"]),
                ],
            },
            {
                "title": "Top Skill Share",
                "subtitle": "How much of the total XP belongs to the top skill.",
                "main_value": format_int(top_skill_xp),
                "main_label": truncate(top_skill_name, 18),
                "segments": share_segments(float(top_skill_xp), float(max(0, tracking["total_xp"] - top_skill_xp))),
                "legend": [
                    (top_skill_name, format_int(top_skill_xp), PALETTE["dark"]),
                    ("Rest", format_int(max(0, tracking["total_xp"] - top_skill_xp)), PALETTE["light"]),
                ],
            },
        ],
        "bar_panel": {
            "title": "Top Skills",
            "subtitle": "XP distribution across the strongest skills.",
            "items": [(skill, xp) for skill, xp in tracking["top_skills"][:7]],
        },
        "lists": [
            {
                "title": "Recent Skill Logs",
                "subtitle": "Newest tracked skill events.",
                "items": recent_skill_lines,
            },
            {
                "title": "Focus Queue",
                "subtitle": "Skills with the strongest current momentum.",
                "items": [f"{skill}  level {1 + (xp // 100)}  {xp} xp" for skill, xp in tracking["top_skills"][:7]],
            },
        ],
        "footer": f"Top skill right now: {top_skill_name}",
    }


def resolve_skill_name(entries: list[dict[str, Any]], requested_skill: str | None) -> str | None:
    skill_xp: Counter[str] = Counter()
    for entry in entries:
        skill_name = str(entry.get("skill") or "").strip()
        if skill_name:
            skill_xp[skill_name] += int(parse_entry_number(entry, "xp") or 0)

    if not skill_xp:
        return requested_skill.strip() if requested_skill else None
    if not requested_skill:
        return skill_xp.most_common(1)[0][0]

    requested_normalized = normalize_text(requested_skill)
    exact = [name for name in skill_xp if normalize_text(name) == requested_normalized]
    if exact:
        return max(exact, key=lambda name: skill_xp[name])

    contains = [
        name
        for name in skill_xp
        if requested_normalized in normalize_text(name) or normalize_text(name) in requested_normalized
    ]
    if contains:
        return max(contains, key=lambda name: skill_xp[name])

    return requested_skill.strip()


def build_skill_report(vault: Path, timezone_name: str, requested_skill: str | None) -> dict[str, Any]:
    tracking = build_tracking_summary(vault, timezone_name)
    all_entries = entries_for_category(tracking["entries"], "skill")
    skill_name = resolve_skill_name(all_entries, requested_skill) or "Skill"
    matching_entries = [entry for entry in all_entries if normalize_text(str(entry.get("skill") or "")) == normalize_text(skill_name)]
    total_skill_xp = sum(int(parse_entry_number(entry, "xp") or 0) for entry in matching_entries)
    recent_count = 0
    boundary = datetime.now(ZoneInfo(timezone_name)) - timedelta(days=14)
    for entry in matching_entries:
        entry_dt = parse_entry_datetime(entry, timezone_name)
        if entry_dt and entry_dt.astimezone(ZoneInfo(timezone_name)) >= boundary:
            recent_count += 1
    last_entry = sort_entries(matching_entries, timezone_name)[0] if matching_entries else None
    share_rest = max(0, tracking["total_xp"] - total_skill_xp)

    return {
        "mode": "skill",
        "subject": skill_name,
        "title": f"Skill Report  {skill_name}",
        "subtitle": f"{vault.name}  focused view for one tracked skill",
        "generated_at": datetime.now(ZoneInfo(timezone_name)).strftime("%Y-%m-%d %H:%M"),
        "stats": [
            {"label": "Skill XP", "value": format_int(total_skill_xp), "note": "total for this skill"},
            {"label": "Level", "value": format_int(1 + (total_skill_xp // 100)), "note": f"{100 - (total_skill_xp % 100) if total_skill_xp % 100 else 100} xp to next"},
            {"label": "Entries", "value": format_int(len(matching_entries)), "note": "logged events"},
            {"label": "Last Activity", "value": sort_entries(matching_entries, timezone_name)[0]["heading"][:10] if matching_entries else "-", "note": truncate(describe_entry(last_entry, "no entries yet"), 24)},
        ],
        "circles": [
            {
                "title": "Skill Level Progress",
                "subtitle": "Progress inside this skill's current level.",
                "main_value": format_int(total_skill_xp % 100),
                "main_label": "xp in level",
                "segments": target_segments(float(total_skill_xp % 100), 100.0),
                "legend": [
                    ("Current", format_int(total_skill_xp % 100), PALETTE["dark"]),
                    ("Next level", "100", PALETTE["light"]),
                ],
            },
            {
                "title": "Share of Total XP",
                "subtitle": "This skill against the rest of all tracked XP.",
                "main_value": format_int(total_skill_xp),
                "main_label": skill_name,
                "segments": share_segments(float(total_skill_xp), float(share_rest)),
                "legend": [
                    (skill_name, format_int(total_skill_xp), PALETTE["dark"]),
                    ("Rest", format_int(share_rest), PALETTE["light"]),
                ],
            },
        ],
        "bar_panel": {
            "title": "Last 7 Days",
            "subtitle": "How often this skill was logged recently.",
            "items": daily_activity(matching_entries, timezone_name, days=7),
        },
        "lists": [
            {
                "title": "Recent Entries",
                "subtitle": "Latest tracked notes for this skill.",
                "items": recent_lines(matching_entries, timezone_name, 7),
            },
            {
                "title": "Micro Focus",
                "subtitle": "Simple follow-up ideas for the next step.",
                "items": [
                    f"Ship one small action for {skill_name}",
                    f"Log one deliberate practice session for {skill_name}",
                    f"Write one next milestone for {skill_name}",
                    f"Review the last note and capture one improvement",
                ],
            },
        ],
        "footer": f"Entries in last 14 days: {recent_count}",
    }


def build_category_report(vault: Path, timezone_name: str, category: str) -> dict[str, Any]:
    tracking = build_tracking_summary(vault, timezone_name)
    entries = entries_for_category(tracking["entries"], category)
    total_xp = sum(int(parse_entry_number(entry, "xp") or 0) for entry in entries)
    last_entry = sort_entries(entries, timezone_name)[0] if entries else None
    last_entry_dt = parse_entry_datetime(last_entry, timezone_name) if last_entry else None
    last_label = last_entry_dt.astimezone(ZoneInfo(timezone_name)).strftime("%d %b") if last_entry_dt else "-"
    entry_share_rest = max(0, tracking["entry_count"] - len(entries))

    title_map = {
        "workout": "Workout Log",
        "nutrition": "Nutrition Log",
        "body": "Body Log",
    }
    subtitle_map = {
        "workout": "training sessions and gym progress",
        "nutrition": "food intake and nutrition tracking",
        "body": "body metrics and recovery tracking",
    }
    goals = {"workout": 4.0, "nutrition": 7.0, "body": 3.0}
    recent_count = sum(value for _, value in daily_activity(entries, timezone_name, days=7))

    if category == "workout":
        stats = [
            {"label": "Entries", "value": format_int(len(entries)), "note": "workout log count"},
            {"label": "This Week", "value": format_int(tracking["workouts_this_week"]), "note": "current weekly count"},
            {"label": "Workout XP", "value": format_int(total_xp), "note": "xp from training"},
            {"label": "Latest", "value": last_label, "note": truncate(describe_entry(last_entry, "no workout yet"), 24)},
        ]
        secondary_value = float(tracking["workouts_this_week"])
        secondary_target = 4.0
        secondary_label = "weekly sessions"
        secondary_subtitle = "Weekly workouts against a four-session target."
    elif category == "nutrition":
        stats = [
            {"label": "Entries", "value": format_int(len(entries)), "note": "nutrition log count"},
            {"label": "Calories Today", "value": format_int(tracking["today_calories"]), "note": "logged today"},
            {"label": "Protein Today", "value": f"{format_int(tracking['today_protein'])}g", "note": "tracked intake"},
            {"label": "Latest", "value": last_label, "note": truncate(describe_entry(last_entry, "no nutrition yet"), 24)},
        ]
        secondary_value = float(tracking["today_protein"])
        secondary_target = 160.0
        secondary_label = "protein today"
        secondary_subtitle = "Protein against a 160g target."
    else:
        latest_body = tracking["latest_body"] or {}
        stats = [
            {"label": "Entries", "value": format_int(len(entries)), "note": "body log count"},
            {"label": "Latest Weight", "value": format_decimal(parse_entry_number(latest_body, "weight_kg"), "kg"), "note": "most recent weight"},
            {"label": "Latest Sleep", "value": format_decimal(parse_entry_number(latest_body, "sleep_hours"), "h"), "note": "most recent sleep"},
            {"label": "Latest", "value": last_label, "note": truncate(describe_entry(last_entry, "no body logs yet"), 24)},
        ]
        secondary_value = float(parse_entry_number(latest_body, "sleep_hours") or 0.0)
        secondary_target = 8.0
        secondary_label = "sleep hours"
        secondary_subtitle = "Sleep against an 8h target."

    return {
        "mode": category,
        "title": title_map[category],
        "subtitle": f"{vault.name}  {subtitle_map[category]}",
        "generated_at": datetime.now(ZoneInfo(timezone_name)).strftime("%Y-%m-%d %H:%M"),
        "stats": stats,
        "circles": [
            {
                "title": "Last 7 Days",
                "subtitle": "How often this log was updated recently.",
                "main_value": format_int(recent_count),
                "main_label": "recent entries",
                "segments": target_segments(float(recent_count), goals[category]),
                "legend": [
                    ("Logged", format_int(recent_count), PALETTE["dark"]),
                    ("Target", format_int(goals[category]), PALETTE["light"]),
                ],
            },
            {
                "title": "Current Target",
                "subtitle": secondary_subtitle,
                "main_value": format_decimal(secondary_value, "g" if category == "nutrition" else "h" if category == "body" else ""),
                "main_label": secondary_label,
                "segments": target_segments(float(secondary_value), secondary_target),
                "legend": [
                    ("Current", format_decimal(secondary_value), PALETTE["dark"]),
                    ("Target", format_decimal(secondary_target), PALETTE["light"]),
                ],
            },
        ],
        "bar_panel": {
            "title": "Activity Timeline",
            "subtitle": "Daily activity across the last seven days.",
            "items": daily_activity(entries, timezone_name, days=7),
        },
        "lists": [
            {
                "title": "Recent Entries",
                "subtitle": "Newest lines in this log.",
                "items": recent_lines(entries, timezone_name, 7),
            },
            {
                "title": "Context",
                "subtitle": "How this log sits inside overall tracking.",
                "items": [
                    f"Total log entries  {len(entries)}",
                    f"XP from this log  {total_xp}",
                    f"Share of all tracked entries  {len(entries)} / {tracking['entry_count'] or 1}",
                    f"Other tracking entries  {entry_share_rest}",
                ],
            },
        ],
        "footer": truncate(describe_entry(last_entry, "No entries recorded yet."), 100),
    }


def build_report(vault: Path, timezone_name: str, mode: str, skill_name: str | None = None) -> dict[str, Any]:
    normalized_mode = normalize_text(mode or "overview")
    if normalized_mode == "overview":
        return build_overview_report(vault, timezone_name)
    if normalized_mode == "graph":
        return build_graph_report(vault, timezone_name)
    if normalized_mode == "health":
        return build_health_report(vault, timezone_name)
    if normalized_mode == "skills":
        return build_skills_report(vault, timezone_name)
    if normalized_mode == "skill":
        return build_skill_report(vault, timezone_name, skill_name)
    if normalized_mode in {"workout", "nutrition", "body"}:
        return build_category_report(vault, timezone_name, normalized_mode)
    return build_overview_report(vault, timezone_name)


def default_output_path(vault: Path, timezone_name: str, mode: str, skill_name: str | None = None) -> Path:
    timestamp = datetime.now(ZoneInfo(timezone_name)).strftime("%Y-%m-%d-%H%M%S")
    suffix = slugify(mode)
    if normalize_text(mode) == "skill" and skill_name:
        suffix = f"{suffix}-{slugify(skill_name)}"
    return vault / REPORTS_DIR / f"{suffix}-{timestamp}.png"


def rasterize_svg(svg: str, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="obsidian-infographic-") as temp_dir:
        temp_root = Path(temp_dir)
        svg_path = temp_root / "report.svg"
        svg_path.write_text(svg, encoding="utf-8")

        magick = shutil.which("magick") or shutil.which("convert")
        if magick:
            command = [
                magick,
                str(svg_path),
                "-strip",
                str(output_path),
            ]
            completed = subprocess.run(command, capture_output=True, text=True)
            if completed.returncode == 0 and output_path.exists():
                return

        qlmanage = shutil.which("qlmanage")
        if qlmanage:
            command = [
                qlmanage,
                "-t",
                "-s",
                "1800",
                "-o",
                str(temp_root),
                str(svg_path),
            ]
            completed = subprocess.run(command, capture_output=True, text=True)
            preview_path = temp_root / (svg_path.name + ".png")
            if completed.returncode == 0 and preview_path.exists():
                output_path.write_bytes(preview_path.read_bytes())
                return

        raise RuntimeError("Unable to rasterize infographic SVG to PNG on this machine.")


def parse_request(text: str | None) -> dict[str, str | None]:
    cleaned = (text or "").strip()
    lowered = normalize_text(cleaned)
    for prefix in SKILL_PREFIXES:
        if lowered.startswith(normalize_text(prefix)):
            return {"mode": "skill", "subject": cleaned[len(prefix) :].strip() or None}

    for mode, aliases in MODE_ALIASES.items():
        for alias in aliases:
            alias_normalized = normalize_text(alias)
            if lowered == alias_normalized or f" {alias_normalized} " in f" {lowered} ":
                return {"mode": mode, "subject": None}

    return {"mode": "overview", "subject": None}


def create_infographic(
    vault: Path,
    timezone_name: str,
    *,
    mode: str = "overview",
    skill_name: str | None = None,
    output_path: Path | None = None,
) -> dict[str, Any]:
    request = parse_request(skill_name if normalize_text(mode) == "overview" and skill_name else mode)
    effective_mode = normalize_text(mode or request["mode"] or "overview") or "overview"
    effective_skill = skill_name
    if effective_mode == "overview" and request["mode"] and request["mode"] != "overview":
        effective_mode = str(request["mode"])
        effective_skill = request["subject"]
    elif effective_mode == "skill" and not effective_skill:
        effective_skill = request["subject"]

    report = build_report(vault, timezone_name, effective_mode, effective_skill)
    final_path = output_path or default_output_path(vault, timezone_name, effective_mode, report.get("subject"))
    svg = render_report_svg(report)
    rasterize_svg(svg, final_path)
    return {
        "png_path": str(final_path),
        "relative_path": final_path.relative_to(vault).as_posix(),
        "generated_at": report["generated_at"],
        "title": report["title"],
        "mode": report["mode"],
        "subject": report.get("subject"),
    }


def command_create(args: argparse.Namespace) -> int:
    vault = head_tool.ensure_vault(args.vault)
    output_path = Path(args.output).expanduser().resolve() if args.output else None
    payload = create_infographic(
        vault,
        args.timezone,
        mode=args.mode,
        skill_name=args.skill,
        output_path=output_path,
    )
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print(payload["png_path"])
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate minimalist Obsidian vault infographics.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    create_parser = subparsers.add_parser("create", help="Generate a PNG infographic for a vault.")
    create_parser.add_argument("vault", help="Path to the vault.")
    create_parser.add_argument("--timezone", default="UTC", help="Timezone for report timestamps.")
    create_parser.add_argument(
        "--mode",
        default="overview",
        choices=["overview", "graph", "health", "skills", "skill", "workout", "nutrition", "body"],
        help="Report type to generate.",
    )
    create_parser.add_argument("--skill", help="Specific skill name for --mode skill.")
    create_parser.add_argument("--output", help="Optional explicit output PNG path.")
    create_parser.add_argument("--json", action="store_true", help="Emit JSON.")
    create_parser.set_defaults(func=command_create)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
