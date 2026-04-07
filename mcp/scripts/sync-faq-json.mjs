#!/usr/bin/env node
/**
 * Regenerates mcp/voiceinsert-mcp/data/faq.json from web/src/app/faq/faq-data.ts
 * Run from repo root: node mcp/scripts/sync-faq-json.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const tsPath = path.join(root, "web/src/app/faq/faq-data.ts");
const outPath = path.join(root, "mcp/voiceinsert-mcp/data/faq.json");

const ts = fs.readFileSync(tsPath, "utf8");
const items = [];
const re =
  /question:\s*"([^"]+)"[\s\S]*?answer:\s*"((?:\\.|[^"])*)"/g;
let m;
while ((m = re.exec(ts)) !== null) {
  const q = m[1].replace(/\\"/g, '"').replace(/\\n/g, "\n");
  const a = m[2].replace(/\\"/g, '"').replace(/\\n/g, "\n");
  items.push({ question: q, answer: a });
}
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(items, null, 2));
console.log(`Wrote ${items.length} FAQ items to ${path.relative(root, outPath)}`);
