"use client";

import { donationPageUrl } from "@/lib/site";

/** Маркер шагов: `~/Desktop/мусор/bulet.svg` → `public/musor-bullet.svg`. */
const MUSOR_BULLET_SRC = "/musor-bullet.svg";

/** Разделитель секций: вектор «свеча» из Desktop/мусор/svecha.svg → `public/svecha.svg`. */
function ImpDivider() {
  return (
    <div className="imp-divider" aria-hidden="true">
      <img
        className="imp-divider-svecha"
        src="/svecha.svg"
        alt=""
        width={25}
        height={60}
        decoding="async"
      />
    </div>
  );
}

export default function HomeClient() {
  const donate = donationPageUrl();

  return (
    <div className="wrap landing-onpage landing-whisper imp-parchment-wrap">
      <header className="landing-hero hero-home landing-reveal imp-hero-card" aria-labelledby="landing-title">
        <h1 id="landing-title" className="imp-sr-only">
          VoiceInsert
        </h1>
        <p className="eyebrow">macOS · Menu bar · On-device speech</p>
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

        {donate ? (
          <div className="landing-cta-block imp-cta-frame">
            <p className="imp-aux-links">
              <a href={donate} rel="noopener noreferrer">
                Buy me a coffee
              </a>
            </p>
          </div>
        ) : null}

        <ol className="steps-list landing-steps" aria-label="Steps after install">
          <li className="step-item">
            <span className="step-icon" aria-hidden="true">
              <img
                className="step-icon-bullet"
                src={MUSOR_BULLET_SRC}
                alt=""
                width={96}
                height={76}
                decoding="async"
              />
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
              <img
                className="step-icon-bullet"
                src={MUSOR_BULLET_SRC}
                alt=""
                width={96}
                height={76}
                decoding="async"
              />
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
              <img
                className="step-icon-bullet"
                src={MUSOR_BULLET_SRC}
                alt=""
                width={96}
                height={76}
                decoding="async"
              />
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
