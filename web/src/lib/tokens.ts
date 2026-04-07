import { createHash, randomBytes } from "crypto";

export function generateAccessToken(): string {
  const raw = randomBytes(32).toString("base64url");
  return `vi_${raw}`;
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}
