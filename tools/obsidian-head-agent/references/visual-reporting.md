# Visual Reporting

## Goal

Turn vault statistics into artifacts that feel polished enough to share or revisit, not just raw console output.

## Design Direction

- minimalist editorial layout rather than generic analytics SaaS
- almost monochrome palette: black, warm gray, paper background
- strong hierarchy with a clear title and 4 hero metrics
- prefer separate images by report mode: overview, graph, health, workout, nutrition, body, skills, and one-skill focus

## What To Show

- core vault metrics: note count, links, tasks, orphan notes
- graph health: connected vs orphaned notes
- progression metrics: total XP, level, top skills
- health metrics when available: workouts, calories, protein
- one explicit focus item or quest

## Output Rules

- default output path: `Reports/Infographics/`
- generate PNG images so Telegram shows a native image preview
- keep labels readable at a glance
- design for mobile-friendly portrait viewing
- avoid cluttering the graph with generated report files when analyzing note connectivity
