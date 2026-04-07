import { macAppZipPath } from "@/lib/site";

const defaultRepo = process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk-public";

/** Карточный логотип Desktop/мусор/logo.svg → public/whisper-card-logo.svg */
const LOGO_CARD_SRC = "/whisper-card-logo.svg";

type SiteHeaderProps = {
  /** Landing: no Download (single CTA on page); no redundant Home link. */
  landingMode?: boolean;
};

export function SiteHeader({ landingMode = false }: SiteHeaderProps) {
  const githubBase = `https://github.com/${defaultRepo}`;

  return (
    <header className="site-header" role="banner">
      <div className="site-header-inner wrap">
        <a
          className={landingMode ? "site-logo site-logo--imps" : "site-logo"}
          href="/"
        >
          {landingMode ? (
            <>
              <img
                className="site-logo-imp-graphic site-logo-imp-card"
                src={LOGO_CARD_SRC}
                alt=""
                width={247}
                height={238}
                decoding="async"
              />
              <span className="site-logo-wordmark">VoiceInsert</span>
            </>
          ) : (
            "VoiceInsert"
          )}
        </a>
        <nav className="site-header-nav-main" aria-label="Main">
          {!landingMode ? (
            <a className="nav-link" href="/">
              Home
            </a>
          ) : null}
          <a className="nav-link" href="/faq">
            FAQ
          </a>
          {!landingMode ? (
            <a className="nav-link nav-link-cta" href={macAppZipPath}>
              Download
            </a>
          ) : null}
          <a className="nav-link nav-link-muted" href={githubBase} rel="noopener noreferrer">
            GitHub
          </a>
        </nav>
      </div>
    </header>
  );
}
