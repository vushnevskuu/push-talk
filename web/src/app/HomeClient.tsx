"use client";

import { useState } from "react";

const defaultRepo = process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk";

export default function HomeClient() {
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const githubBase = `https://github.com/${defaultRepo}`;
  const zipUrl = `${githubBase}/releases/latest/download/VoiceInsert-macos.zip`;

  async function startTrial() {
    setError(null);
    setLoading(true);
    try {
      const res = await fetch("/api/create-checkout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.trim() }),
      });
      const data = (await res.json()) as { url?: string; error?: string };
      if (!res.ok) {
        throw new Error(data.error ?? "Checkout failed");
      }
      if (!data.url) {
        throw new Error("No checkout URL");
      }
      const checkoutId = (data as { checkoutId?: string }).checkoutId;
      if (checkoutId && typeof window !== "undefined") {
        try {
          window.sessionStorage.setItem("vi_checkout_id", checkoutId);
        } catch {
          /* ignore */
        }
      }
      window.location.href = data.url;
    } catch (e) {
      setError(e instanceof Error ? e.message : "Unknown error");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="wrap">
      <header style={{ paddingBlock: "clamp(2rem, 8vw, 4rem) 2rem" }}>
        <nav className="site-header-nav" aria-label="Primary">
          <a href="/faq">FAQ</a>
        </nav>
        <p className="eyebrow">macOS · Menu bar</p>
        <h1>VoiceInsert</h1>
        <p className="lede">
          Hold a shortcut, speak, release—text goes into the focused field or into your Obsidian vault as Markdown. No
          cloud required for dictation.
        </p>
        <div className="cta-row">
          <a className="btn-primary" href={zipUrl}>
            Download for Mac
          </a>
          <a className="btn-secondary" href={githubBase}>
            Source on GitHub
          </a>
        </div>

        <div className="card">
          <h2>Start trial</h2>
          <p className="price-note">
            <strong>$1</strong> to start a <strong>7-day trial</strong>, then <strong>$10/month</strong> billed through
            Airwallex. After payment, copy your access token on the success page and paste it into VoiceInsert Settings.
          </p>
          <div style={{ marginTop: "1rem" }}>
            <label htmlFor="email">Email</label>
            <input
              id="email"
              type="email"
              name="email"
              autoComplete="email"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </div>
          {error ? <p className="err">{error}</p> : null}
          <div style={{ marginTop: "1rem" }}>
            <button
              type="button"
              className="btn-primary"
              disabled={loading || !email.includes("@")}
              onClick={() => void startTrial()}
            >
              {loading ? "Redirecting…" : "Start trial — $1"}
            </button>
          </div>
        </div>

        <ul
          style={{
            listStyle: "none",
            padding: 0,
            margin: "2rem 0 0",
            display: "grid",
            gap: "0.75rem",
          }}
        >
          {[
            "Works in any app with a text field—Safari, Notes, IDEs, and more.",
            "Optional second shortcut saves structured notes under Voice Captures/ in Obsidian.",
            "Microphone and speech stay on device; you control Accessibility and shortcuts in Settings.",
          ].map((t) => (
            <li key={t} style={{ position: "relative", paddingLeft: "1.5rem", color: "var(--color-muted)" }}>
              <span
                style={{
                  position: "absolute",
                  left: 0,
                  top: "0.55em",
                  width: "0.5rem",
                  height: "0.5rem",
                  borderRadius: "50%",
                  background: "linear-gradient(135deg, var(--hud-amber), var(--hud-coral))",
                }}
              />
              {t}
            </li>
          ))}
        </ul>
      </header>

      <section id="requirements" style={{ borderTop: "1px solid var(--color-border)", padding: "2rem 0" }}>
        <h2 className="eyebrow" style={{ marginBottom: "1rem" }}>
          Requirements
        </h2>
        <div className="card" style={{ marginTop: 0 }}>
          <p style={{ color: "var(--color-muted)", margin: 0, fontSize: "0.95rem" }}>
            <strong style={{ color: "var(--color-text)" }}>macOS 13+</strong> · Apple Silicon or Intel. First launch: if
            Gatekeeper blocks the app, use Control-click → Open.
          </p>
        </div>
      </section>

      <section className="seo-section" aria-labelledby="why-voiceinsert">
        <h2 id="why-voiceinsert" className="seo-section-title">
          Why VoiceInsert for Mac dictation
        </h2>
        <p className="seo-section-lead">
          VoiceInsert is a <strong>menu bar dictation app</strong> for macOS built around a <strong>hold-to-talk</strong>{" "}
          workflow: press and hold your shortcut, speak, release—recognized text is typed or pasted into whatever app
          already has keyboard focus (browsers, Slack, Xcode, VS Code, Obsidian, Notes, and more). Unlike cloud
          transcription services, <strong>speech recognition runs on your Mac</strong> using Apple’s Speech framework, so
          your audio is not sent to a third-party ASR API for the recognition step.
        </p>
        <p className="seo-section-lead">
          Power users pair it with a second shortcut for <strong>Obsidian voice notes</strong>: capture is filed into{" "}
          <strong>Voice Captures</strong> folders (Ideas, Tasks, Meetings, Journal, Notes, Inbox) as Markdown. It is a
          lightweight alternative when you want <strong>push-to-talk dictation</strong> without switching to the
          Dictation palette in every app.
        </p>
        <p className="seo-section-lead">
          <a href="/faq">Read the FAQ</a> for comparisons with Apple Dictation, Cursor, privacy, permissions, and
          troubleshooting.
        </p>
      </section>
    </div>
  );
}
