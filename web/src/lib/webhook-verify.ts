import { createHmac, timingSafeEqual } from "crypto";

/**
 * Airwallex may send `x-signature` + timestamp; exact format depends on dashboard version.
 * Configure AIRWALLEX_WEBHOOK_SECRET from the Airwallex webhook settings.
 */
export function verifyAirwallexWebhook(rawBody: string, signatureHeader: string | null): boolean {
  const secret = process.env.AIRWALLEX_WEBHOOK_SECRET;
  if (!secret) {
    return process.env.NODE_ENV !== "production";
  }
  if (!signatureHeader) {
    return false;
  }

  const trimmed = signatureHeader.trim();
  const direct = createHmac("sha256", secret).update(rawBody, "utf8").digest("hex");
  if (safeEqualHex(direct, trimmed)) {
    return true;
  }

  const v1 = trimmed.match(/v1=([a-f0-9]+)/i)?.[1];
  if (v1 && safeEqualHex(direct, v1)) {
    return true;
  }

  return false;
}

function safeEqualHex(a: string, b: string): boolean {
  try {
    const ba = Buffer.from(a, "hex");
    const bb = Buffer.from(b, "hex");
    if (ba.length !== bb.length) {
      return false;
    }
    return timingSafeEqual(ba, bb);
  } catch {
    return false;
  }
}
