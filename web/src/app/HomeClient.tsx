"use client";

import { useId } from "react";
import { ImpHeroFlank } from "@/components/ImpOrnaments";
import { donationPageUrl } from "@/lib/site";

const defaultRepo = process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk-public";

function ImpDivider() {
  const sid = useId().replace(/:/g, "");
  const pid = `imp-scallop-${sid}`;
  return (
    <div className="imp-divider" aria-hidden="true">
      <svg className="imp-divider-svg" viewBox="0 0 600 16" preserveAspectRatio="none" role="presentation">
        <defs>
          <pattern id={pid} width="28" height="16" patternUnits="userSpaceOnUse">
            <path
              d="M0 8 Q7 2 14 8 Q21 14 28 8"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.15"
              vectorEffect="non-scaling-stroke"
            />
          </pattern>
        </defs>
        <rect width="100%" height="16" fill={`url(#${pid})`} />
      </svg>
    </div>
  );
}

export default function HomeClient() {
  const githubBase = `https://github.com/${defaultRepo}`;
  const zipUrl = "/VoiceInsert-macos.zip";
  const donate = donationPageUrl();

  return (
    <div className="wrap landing-onpage landing-whisper imp-parchment-wrap">
      <header className="landing-hero hero-home landing-reveal imp-hero-card" aria-labelledby="landing-title">
        <div className="imp-hero-motif-watermark" aria-hidden />
        <p className="eyebrow">macOS · Menu bar · On-device speech</p>
        <p className="imp-era-tag">
          Styling after the <cite>Whispering Imps</cite> playing-card art — pencil devils, cream stock, crimson ink.
        </p>
        <div className="imp-hero-cluster">
          <ImpHeroFlank />
          <div className="imp-hero-center">
            <h1 id="landing-title">VoiceInsert</h1>
          </div>
          <ImpHeroFlank flip />
        </div>
        <p className="lede hero-lede landing-lede">
          Hold a shortcut, speak, release — text lands in the focused field. Optional second shortcut saves Markdown into
          your Obsidian vault. Recognition stays on your Mac.
        </p>
      </header>

      <ImpDivider />

      <article className="landing-article landing-reveal landing-reveal-delay-1" aria-labelledby="use-heading">
        <h2 id="use-heading" className="landing-h2">
          Install and use
        </h2>
        <p className="landing-lead">
          <strong className="landing-strong">Free</strong> — no account or token. Unzip, drag VoiceInsert.app to
          Applications, open once. If Gatekeeper blocks it, Control-click → Open.
        </p>

        <div className="landing-cta-block imp-cta-frame" id="download">
          <a className="btn-download-solo" href={zipUrl}>
            Download for Mac
          </a>
          <p className="imp-aux-links">
            <a href={`${githubBase}/releases`} rel="noopener noreferrer">
              GitHub releases
            </a>
            {donate ? (
              <>
                <span className="imp-aux-sep" aria-hidden="true">
                  ·
                </span>
                <a href={donate} rel="noopener noreferrer">
                  Buy me a coffee
                </a>
              </>
            ) : null}
          </p>
        </div>

        <ol className="steps-list landing-steps" aria-label="Steps after install">
          <li className="step-item">
            <span className="step-icon" aria-hidden="true">
              <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="1.5">
                <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z" />
                <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
                <line x1="12" y1="19" x2="12" y2="23" />
              </svg>
            </span>
            <div>
              <strong className="step-title">Hold your shortcut</strong>
              <p className="step-text">
                Speak while the key is held; release to insert — browsers, Slack, IDEs, Obsidian, Notes, and more.
              </p>
            </div>
          </li>
          <li className="step-item">
            <span className="step-icon" aria-hidden="true">
              <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="1.5">
                <rect x="3" y="11" width="18" height="11" rx="1" />
                <path d="M7 11V7a5 5 0 0 1 10 0v4" />
              </svg>
            </span>
            <div>
              <strong className="step-title">Grant permissions once</strong>
              <p className="step-text">
                Microphone, Speech, Accessibility, Input Monitoring — explained in Settings. No third-party cloud ASR.
              </p>
            </div>
          </li>
          <li className="step-item">
            <span className="step-icon" aria-hidden="true">
              <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="1.5">
                <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                <path d="M14 2v6h6M16 13H8M16 17H8M10 9H8" />
              </svg>
            </span>
            <div>
              <strong className="step-title">Optional Obsidian capture</strong>
              <p className="step-text">
                Second shortcut files Markdown under Voice Captures/ (Ideas, Tasks, Meetings, Journal, Notes, Inbox).
              </p>
            </div>
          </li>
        </ol>
      </article>

      <ImpDivider />

      <section className="landing-details landing-reveal landing-reveal-delay-2" aria-labelledby="details-heading">
        <h2 id="details-heading" className="landing-h2">
          Requirements
        </h2>
        <p className="landing-prose landing-prose-tight">
          <strong>macOS 13+</strong>, Apple Silicon or Intel. Hold-to-talk menu bar app: types or pastes into the focused
          app using Apple&apos;s on-device Speech framework.
        </p>
      </section>
    </div>
  );
}
