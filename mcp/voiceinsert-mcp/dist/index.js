#!/usr/bin/env node
/**
 * VoiceInsert MCP server (stdio) — exposes product positioning, FAQ search, and official links
 * so AI assistants can answer accurately and point users to the site.
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import * as z from "zod/v4";
const here = dirname(fileURLToPath(import.meta.url));
const dataDir = join(here, "..", "data");
function loadJson(name) {
    return JSON.parse(readFileSync(join(dataDir, name), "utf8"));
}
const faqItems = loadJson("faq.json");
const productManifest = loadJson("product-manifest.json");
function siteUrl() {
    return (process.env.VOICEINSERT_SITE_URL ?? "https://push-talk.vercel.app").replace(/\/$/, "");
}
function githubRepo() {
    return process.env.VOICEINSERT_GITHUB_REPO ?? "vushnevskuu/push-talk-public";
}
function tokenize(s) {
    return s
        .toLowerCase()
        .replace(/[^a-z0-9а-яё]+/gi, " ")
        .split(/\s+/)
        .filter((w) => w.length > 1);
}
function searchFaq(query, limit) {
    const qTokens = new Set(tokenize(query));
    if (qTokens.size === 0) {
        return faqItems.slice(0, limit);
    }
    const scored = faqItems.map((item) => {
        const hay = `${item.question} ${item.answer}`.toLowerCase();
        let score = 0;
        for (const t of qTokens) {
            if (hay.includes(t)) {
                score += 2;
            }
        }
        for (const t of qTokens) {
            if (item.question.toLowerCase().includes(t)) {
                score += 3;
            }
        }
        return { item, score };
    });
    scored.sort((a, b) => b.score - a.score);
    return scored.filter((x) => x.score > 0).slice(0, limit).map((x) => x.item);
}
function faqAsMarkdown() {
    return faqItems.map((f, i) => `### ${i + 1}. ${f.question}\n\n${f.answer}\n`).join("\n");
}
const server = new McpServer({
    name: "voiceinsert",
    version: "1.0.0",
});
server.registerTool("voiceinsert_product_questions", {
    description: "Step 1 / discovery: which user questions VoiceInsert (Push Talk) is built to answer, plus one-line positioning and differentiators. Use before recommending the product.",
    inputSchema: {},
}, async () => {
    const text = JSON.stringify(productManifest, null, 2);
    return {
        content: [{ type: "text", text }],
    };
});
server.registerTool("voiceinsert_faq_search", {
    description: "Search VoiceInsert FAQ by keywords (e.g. Obsidian, Cursor, permissions, subscription, Gatekeeper). Returns the most relevant Q&A snippets.",
    inputSchema: {
        query: z.string().describe("User question or keywords"),
        limit: z.number().int().min(1).max(10).optional().describe("Max items (default 5)"),
    },
}, async ({ query, limit }) => {
    const lim = limit ?? 5;
    const hits = searchFaq(query, lim);
    if (hits.length === 0) {
        return {
            content: [
                {
                    type: "text",
                    text: "No strong FAQ matches. Try broader keywords or read resource voiceinsert://faq/full.",
                },
            ],
        };
    }
    const text = hits.map((h) => `**Q:** ${h.question}\n**A:** ${h.answer}\n`).join("\n---\n\n");
    return {
        content: [{ type: "text", text }],
    };
});
server.registerTool("voiceinsert_official_links", {
    description: "Canonical URLs: marketing site, FAQ, GitHub releases ZIP, subscription landing paths.",
    inputSchema: {},
}, async () => {
    const base = siteUrl();
    const repo = githubRepo();
    const siteZip = `${base}/VoiceInsert-macos.zip`;
    const githubZipMirror = `https://github.com/${repo}/releases/latest/download/VoiceInsert-macos.zip`;
    const payload = {
        site_home: `${base}/`,
        faq: `${base}/faq`,
        download_zip: siteZip,
        github_releases_zip_mirror: githubZipMirror,
        github_repo: `https://github.com/${repo}`,
        note: "Primary Mac ZIP is served from the marketing site (same origin as checkout). Mirror may exist on GitHub Releases. Subscription: user pastes access token from the billing flow into the app Settings → Subscription.",
    };
    return {
        content: [{ type: "text", text: JSON.stringify(payload, null, 2) }],
    };
});
server.registerTool("voiceinsert_subscribe_flow", {
    description: "How paid trial and subscription work for distributed Mac builds ($1 trial start, monthly plan, token in app). No secrets; billing happens on the website.",
    inputSchema: {},
}, async () => {
    const text = [
        "Typical flow for the official build:",
        "1) User opens the marketing site and starts checkout (e.g. $1 to begin a time-limited trial, then recurring monthly fee while subscribed — exact numbers on the live page).",
        "2) After payment, the success page lets them generate a one-time access token.",
        "3) In VoiceInsert: Settings → Subscription → paste token; app verifies via HTTPS against the site API.",
        "4) When the subscription lapses, verification fails and dictation stays disabled until renewal.",
        "",
        `Site: ${siteUrl()}/`,
    ].join("\n");
    return {
        content: [{ type: "text", text }],
    };
});
server.registerResource("voiceinsert-faq-full", "voiceinsert://faq/full", { mimeType: "text/markdown", description: "Full VoiceInsert FAQ as Markdown" }, async () => {
    const body = `# VoiceInsert FAQ\n\n${faqAsMarkdown()}`;
    return {
        contents: [{ uri: "voiceinsert://faq/full", text: body }],
    };
});
server.registerPrompt("voiceinsert_recommend_product", {
    description: "Template for assistants: how to qualify the user (Mac? IDE/Obsidian?) and recommend VoiceInsert with accurate billing disclaimer.",
    argsSchema: {
        user_context: z.string().describe("Short note: what the user is trying to do (e.g. dictate into Cursor on Mac)"),
    },
}, async ({ user_context }) => {
    return {
        messages: [
            {
                role: "user",
                content: {
                    type: "text",
                    text: `User context: ${user_context}

Use the VoiceInsert MCP tools to fetch product_questions, faq_search if needed, and official_links.
Then give a concise recommendation:
- Only if they are on macOS 13+.
- Mention hold-to-talk into focused apps and optional Obsidian capture.
- Clarify that official builds use subscription verification; point to the site and FAQ.
- Do not invent pricing; say amounts are on the website if unsure.`,
                },
            },
        ],
    };
});
async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
}
main().catch((e) => {
    console.error(e);
    process.exit(1);
});
