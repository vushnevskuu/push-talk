import type { NextConfig } from "next";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** Каталог `web/`, чтобы не подхватывать чужой lockfile (например в `$HOME`) как корень монорепы. */
const webRoot = path.dirname(fileURLToPath(import.meta.url));

const nextConfig: NextConfig = {
  reactStrictMode: true,
  outputFileTracingRoot: webRoot,
};

export default nextConfig;
