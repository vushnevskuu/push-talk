/**
 * Canonical site origin for metadata, sitemap, and JSON-LD.
 * Set NEXT_PUBLIC_SITE_URL in production (https://your-domain.com — no trailing slash).
 */
export function getSiteUrl(): URL {
  const explicit = process.env.NEXT_PUBLIC_SITE_URL?.trim();
  if (explicit) {
    return new URL(explicit.endsWith("/") ? explicit.slice(0, -1) : explicit);
  }
  const vercel = process.env.VERCEL_URL?.trim();
  if (vercel) {
    const host = vercel.startsWith("http") ? vercel : `https://${vercel}`;
    return new URL(host.endsWith("/") ? host.slice(0, -1) : host);
  }
  return new URL("http://localhost:3000");
}

export function siteOrigin(): string {
  return getSiteUrl().origin;
}

/** Mac app bundle ZIP served from `web/public`. */
export const macAppZipPath = "/VoiceInsert-macos.zip";

/**
 * Tip link: Vercel env first, then optional hardcoded fallback (one place if you skip env).
 * Set `NEXT_PUBLIC_DONATION_URL` in production, or paste your Buy Me a Coffee / Ko-fi URL below.
 */
const DONATION_URL_SITE_FALLBACK = "";

function parseHttpUrl(raw: string): string | null {
  try {
    const u = new URL(raw);
    if (u.protocol === "https:" || u.protocol === "http:") {
      return u.href;
    }
  } catch {
    /* ignore */
  }
  return null;
}

export function donationPageUrl(): string | null {
  const raw = process.env.NEXT_PUBLIC_DONATION_URL?.trim() || DONATION_URL_SITE_FALLBACK.trim();
  if (!raw) {
    return null;
  }
  return parseHttpUrl(raw);
}

export function macAppZipAbsoluteUrl(): string {
  return `${siteOrigin()}${macAppZipPath}`;
}

/** Shown in footer; override with NEXT_PUBLIC_SITE_AUTHOR_NAME on Vercel. */
const defaultAuthorName = "Aleksey Vishnevsky";

/** Full profile URL; override with NEXT_PUBLIC_SITE_AUTHOR_LINKEDIN. */
const defaultAuthorLinkedIn = "https://www.linkedin.com/in/vushnevskuu/";

export function siteAuthorName(): string {
  const fromEnv = process.env.NEXT_PUBLIC_SITE_AUTHOR_NAME?.trim();
  return fromEnv || defaultAuthorName;
}

export function siteAuthorLinkedInUrl(): string {
  const fromEnv = process.env.NEXT_PUBLIC_SITE_AUTHOR_LINKEDIN?.trim();
  if (fromEnv) {
    try {
      const u = new URL(fromEnv);
      if (u.protocol === "https:" || u.protocol === "http:") {
        return u.href;
      }
    } catch {
      /* use default */
    }
  }
  return defaultAuthorLinkedIn;
}
