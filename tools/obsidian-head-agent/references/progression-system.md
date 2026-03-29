# Progression System

## Goal

Make the Obsidian Head Agent feel like a personal operator plus a lightweight RPG layer.

The system should:

- reward consistency,
- make invisible progress visible,
- connect work, health, and execution,
- and surface the next best quest.

## Core Stats

- `level`: derived from total XP
- `total_xp`: sum of tracked progress events
- `xp_to_next_level`: remaining XP before the next level
- `top_skills`: highest XP skill buckets
- `current_quest`: one action that moves the system forward

## Suggested Skills

Use both life and work skills:

- `coding`
- `writing`
- `shipping`
- `research`
- `focus`
- `strength`
- `conditioning`
- `nutrition`
- `recovery`

Add custom skills when the user repeatedly names a domain.

## XP Heuristics

Keep the system simple and legible:

- generic skill log: `+20 xp`
- workout log: `+25 xp`
- nutrition log: `+10 xp`
- body/recovery log: `+8 xp`

The point is momentum, not fake precision.

## Logging Patterns

Examples that should be easy to capture from Telegram:

- `skill: writing | drafted landing page outline`
- `gym: bench 80x5x3`
- `food: 2200 kcal 160 protein`
- `weight 82.4`
- `sleep 7.5`

## Interpretation Rules

- Do not pretend gamified XP is objective truth.
- Treat it as a motivational overlay on top of real evidence.
- Explain that a higher skill score means more logged momentum, not perfect mastery.
