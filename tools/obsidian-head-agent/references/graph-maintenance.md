# Graph Maintenance

## Goal

Keep the Obsidian vault usable as a connected graph, not just a folder of Markdown files.

The graph layer should:

- reduce orphan notes,
- reinforce meaningful relationships,
- support Graph View and mind-map style exploration,
- and avoid spammy low-value linking.

## Linking Rules

- Prefer high-signal links over blanket keyword linking.
- Add bidirectional links when two notes should reference each other semantically.
- Use a compact `## Related` section when a contextual paragraph is not obvious.
- Avoid linking system files like `Memory.md`, Telegram logs, and tracking logs into the main idea graph.

## Operational Patterns

- `graph-stats`: inspect hubs, orphan notes, unresolved links, and low-link notes
- `suggest-links`: generate candidate pairs worth connecting
- `connect-note`: add missing wiki-links between existing notes

## Good Link Signals

- shared tags,
- shared project or idea context,
- repeated title/topic overlap,
- explicit references in the body,
- one note clearly depending on another for context.

## Bad Link Signals

- same generic noun but unrelated intent,
- broad taxonomy links that add no retrieval value,
- linking every daily note to everything,
- system and log notes leaking into the main graph.

## Maintenance Loop

1. Review graph stats.
2. Inspect orphan and low-link notes.
3. Generate suggestions.
4. Apply only the strong links.
5. Re-check graph stats and avoid over-linking.
