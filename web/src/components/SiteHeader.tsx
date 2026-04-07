import { macAppZipPath } from "@/lib/site";

const defaultRepo = process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk-public";

/** Cropped from user sketch sheet — whispering imps motif beside the wordmark. */
const LOGO_IMPS_SRC = "/logo-whispering-imps.png";

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
                className="site-logo-imp-graphic"
                src={LOGO_IMPS_SRC}
                alt=""
                width={84}
                height={68}
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
