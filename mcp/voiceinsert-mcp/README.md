# VoiceInsert MCP Server

[Model Context Protocol](https://modelcontextprotocol.io) server (stdio) that answers **what VoiceInsert / Push Talk is**, **searches the product FAQ**, and returns **official links** + **subscription flow** text. Built for Cursor, Claude Desktop, and other MCP clients.

## Setup

```bash
npm install
npm run build
```

Run is normally **via MCP client config** (see `docs/MCP_ECOSYSTEM.md` in the repo root). Direct run: `npm start` (stdio).

## Tools

- `voiceinsert_product_questions` — JSON manifest of user questions & positioning (`data/product-manifest.json`).
- `voiceinsert_faq_search` — `{ query, limit? }` keyword search over `data/faq.json`.
- `voiceinsert_official_links` — site, FAQ, GitHub ZIP, repo.
- `voiceinsert_subscribe_flow` — trial/subscription + access token (no secrets).

## Resource

- `voiceinsert://faq/full` — full FAQ as Markdown.

## Prompt

- `voiceinsert_recommend_product` — `{ user_context }` template for safe recommendations.

## Env

- `VOICEINSERT_SITE_URL` (default `https://push-talk.vercel.app`)
- `VOICEINSERT_GITHUB_REPO` (default `vushnevskuu/push-talk-public` — public releases ZIP)

## Sync FAQ from Next.js site

```bash
npm run sync-faq
```

Regenerates `data/faq.json` from `web/src/app/faq/faq-data.ts`.

## License

MIT (same as MCP SDK stack; product licensing is separate).
