import type { NextConfig } from "next";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // Monorepo: app lives in web/; trace from repository root so Vercel bundles server files correctly.
  outputFileTracingRoot: path.join(__dirname, ".."),
};

export default nextConfig;
