# Memory Schema

`Memory.md` is the persistent working memory for the Obsidian Head Agent. Keep it readable by a human and easy to edit incrementally.

## Default Location

- Preferred path: `<vault>/Memory.md`
- If the user already has a system folder, placing `Memory.md` there is also fine.

## File Sections

Keep these sections in this order when possible:

1. `## Sync Metadata`
2. `## Active Focus`
3. `## Change Log`
4. `## Player Profile`
5. `## Skills Registry`
6. `## Body And Recovery`
7. `## Nutrition Snapshot`
8. `## Ideas Registry`
9. `## Projects Registry`
10. `## Themes Registry`
11. `## Cleanup Registry`
12. `## Reflection Registry`

## Entry Conventions

- Use stable IDs such as `idea-20260320-01` or `project-20260320-01`.
- Prefer one heading per entity.
- Keep fields as flat bullet lists so the file stays easy to patch.
- Update `last_seen`, `status`, `next_step`, and `evidence` whenever something meaningful changes.
- Keep uncertainty explicit instead of forcing false precision.

## Ideas Registry

Each idea should track:

- `title`
- `summary`
- `source_notes`
- `status`
- `first_seen`
- `last_seen`
- `confidence`
- `next_step`
- `related_ideas`
- `evidence`
- `implemented_flag`

## Player Profile

Track a compact RPG-like summary for motivation and pacing:

- `level`
- `total_xp`
- `xp_to_next_level`
- `top_skills`
- `current_quest`
- `current_streak`

## Skills Registry

Each tracked skill should include:

- `skill`
- `level`
- `xp`
- `status`
- `evidence`
- `recent_progress`
- `next_upgrade`

Examples:

- writing
- shipping
- coding
- strength
- nutrition
- recovery
- focus

## Projects Registry

Each project should track:

- `name`
- `summary`
- `status`
- `progress_state`
- `blockers`
- `next_step`
- `related_notes`
- `last_activity`

## Themes Registry

Each theme should track:

- `theme`
- `mentions_count`
- `related_notes`
- `trend`
- `importance_estimate`

## Cleanup Registry

Each cleanup item should track:

- `title`
- `classification`
- `reason`
- `confidence`
- `suggested_action`
- `confirmation_required`
- `resolved_state`

## Reflection Registry

Each reflection should track:

- `pattern`
- `evidence`
- `interpretation`
- `suggestion`

## Body And Recovery

Keep compact body-health state here:

- `latest_weight_kg`
- `latest_sleep_hours`
- `latest_steps`
- `latest_workout_summary`
- `health_focus`

## Nutrition Snapshot

Use this section for the latest nutrition picture:

- `daily_calorie_target`
- `daily_protein_target`
- `latest_calories`
- `latest_protein_g`
- `notes`

## Change Log

Use short dated bullets:

```markdown
- 2026-03-20: created memory file and added first idea/project entries.
- 2026-03-21: marked `project-20260320-01` as `blocked`; blocker is missing research.
```

## Update Rules

- Preserve old state in the log when status meaningfully changes.
- If the user explicitly says an item is done, blocked, paused, merged, archived, or deleted, update memory immediately.
- Do not silently drop entities. Mark them `dropped`, `archived`, `duplicate`, or `deleted`.
- When the evidence is weak, use `likely-*` or a short uncertainty note.
- For progression data, prefer stable skill names and update XP/level rather than creating duplicates for the same skill.
