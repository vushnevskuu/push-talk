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
    <div className="wrap home-page">
      <header className="hero-home">
        <p className="eyebrow">macOS · Menu bar</p>
        <h1>VoiceInsert</h1>
        <p className="lede hero-lede">
          Hold a shortcut, speak, release—text goes into the focused field or into your Obsidian vault as Markdown. No
          cloud required for dictation.
        </p>
      </header>

      <section className="path-section" aria-labelledby="get-voiceinsert-heading">
        <h2 id="get-voiceinsert-heading" className="section-title">
          Get VoiceInsert
        </h2>
        <p className="section-intro">
          <strong>Official Mac builds</strong> check your subscription online (trial or paid period). Download the app,
          start billing with <strong>$1</strong> for the trial where offered, then paste the one-time access token into
          the app’s Settings → Subscription. Without an active plan, dictation stays locked.
        </p>

        <div className="path-grid">
          <div id="download" className="path-card path-card-free" tabIndex={-1}>
            <h3 className="path-card-title">Download for Mac</h3>
            <p className="path-card-desc">
              Latest release ZIP from GitHub. After install, add your token from the billing site so the app can verify
              your trial or subscription.
            </p>
            <div className="cta-row path-card-cta">
              <a className="btn-primary" href={zipUrl}>
                Download for Mac
              </a>
              <a className="btn-secondary" href={githubBase} rel="noopener noreferrer">
                GitHub Releases
              </a>
            </div>
          </div>

          <div className="path-card path-card-trial">
            <div className="path-card-heading-row">
              <h3 className="path-card-title">Start trial</h3>
              <span className="badge-billing">Billing</span>
            </div>
            <p className="price-note path-card-pricing">
              <strong>$1</strong> starts a <strong>7-day trial</strong>, then <strong>$10/month</strong> via Airwallex.
              After checkout, open the success page, generate your token once, and paste it in VoiceInsert → Settings →
              Subscription.
            </p>
            <label htmlFor="email">Email for receipt</label>
            <input
              id="email"
              type="email"
              name="email"
              autoComplete="email"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="input-field"
            />
            {error ? <p className="err">{error}</p> : null}
            <div className="trial-actions">
              <button
                type="button"
                className="btn-primary"
                disabled={loading || !email.includes("@")}
                aria-busy={loading}
                aria-label={loading ? "Redirecting to checkout" : "Start trial for one dollar"}
                onClick={() => void startTrial()}
              >
                {loading ? "Redirecting…" : "Start trial — $1"}
              </button>
            </div>
          </div>
        </div>
      </section>

      <section className="how-section" aria-labelledby="how-it-works-heading">
        <h2 id="how-it-works-heading" className="section-title">
          How it works
        </h2>
        <ol className="steps-list">
          <li className="step-item">
            <span className="step-icon" aria-hidden="true">
              <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z" />
                <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
                <line x1="12" y1="19" x2="12" y2="23" />
              </svg>
            </span>
            <div>
              <strong className="step-title">Hold your shortcut</strong>
              <p className="step-text">Speak while the key is held; release to insert text where the cursor is.</p>
            </div>
          </li>
          <li className="step-item">
            <span className="step-icon" aria-hidden="true">
              <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2">
                <rect x="3" y="11" width="18" height="11" rx="2" />
                <path d="M7 11V7a5 5 0 0 1 10 0v4" />
              </svg>
            </span>
            <div>
              <strong className="step-title">Grant permissions once</strong>
              <p className="step-text">Microphone and Accessibility—speech stays on device with Apple’s framework.</p>
            </div>
          </li>
          <li className="step-item">
            <span className="step-icon" aria-hidden="true">
              <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                <path d="M14 2v6h6M16 13H8M16 17H8M10 9H8" />
              </svg>
            </span>
            <div>
              <strong className="step-title">Optional Obsidian capture</strong>
              <p className="step-text">A second shortcut files Markdown under Voice Captures/ in your vault.</p>
            </div>
          </li>
        </ol>
      </section>

      <section aria-labelledby="highlights-heading">
        <h2 id="highlights-heading" className="section-title">
          Highlights
        </h2>
        <ul className="feature-list">
          {[
            "Works in any app with a text field—Safari, Notes, IDEs, and more.",
            "Optional second shortcut saves structured notes under Voice Captures/ in Obsidian.",
            "Microphone and speech stay on device; you control Accessibility and shortcuts in Settings.",
          ].map((t) => (
            <li key={t} className="feature-item">
              {t}
            </li>
          ))}
        </ul>
      </section>

      <section id="requirements" className="requirements-section" aria-labelledby="requirements-heading">
        <h2 id="requirements-heading" className="section-title">
          Requirements
        </h2>
        <div className="card requirements-card">
          <p className="requirements-text">
            <strong>macOS 13+</strong> · Apple Silicon or Intel. First launch: if Gatekeeper blocks the app, use
            Control-click → Open.
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
          transcription services, <strong>speech recognition runs on your Mac</strong> using Apple’s Speech framework,
          so your audio is not sent to a third-party ASR API for the recognition step.
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
