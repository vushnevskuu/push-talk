import { createHash, timingSafeEqual } from "crypto";

/**
 * Скрытый вход: логин/пароль по умолчанию зашиты как base64 (не секьюрность, только «не на виду»).
 * В проде задайте VOICEINSERT_CREW_LOGIN и VOICEINSERT_CREW_PASSWORD в Vercel — тогда встроенные значения не используются.
 */
const B64_LOGIN = "Y3Jldy52b2ljZWluc2VydA==";
const B64_PASSWORD = "Vmk5cjJMbThRcDRzTnoxIQ==";

function expectedLogin(): string {
  const env = process.env.VOICEINSERT_CREW_LOGIN?.trim();
  if (env) {
    return env;
  }
  return Buffer.from(B64_LOGIN, "base64").toString("utf8");
}

function expectedPassword(): string {
  const env = process.env.VOICEINSERT_CREW_PASSWORD?.trim();
  if (env) {
    return env;
  }
  return Buffer.from(B64_PASSWORD, "base64").toString("utf8");
}

function hashEqual(a: string, b: string): boolean {
  const ha = createHash("sha256").update(a, "utf8").digest();
  const hb = createHash("sha256").update(b, "utf8").digest();
  return ha.length === hb.length && timingSafeEqual(ha, hb);
}

export function verifyCrewCredentials(login: string, password: string): boolean {
  const l = login.trim();
  const p = password;
  return hashEqual(l, expectedLogin()) && hashEqual(p, expectedPassword());
}

/** Один фиксированный «клиент» в БД для бесплатного доступа. */
export const CREW_GATE_EMAIL = "crew-gate@voiceinsert.internal";
export const CREW_GATE_SUBSCRIPTION_ID = "sub_internal_crew_gate";
