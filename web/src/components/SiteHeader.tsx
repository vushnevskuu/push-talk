import { macAppZipPath } from "@/lib/site";

const defaultRepo = process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk-public";

const HUMAN_TRANCE_SRC = "/human-trance.svg";
/** Кнопка-вектор: ~/Desktop/мусор/KNOPKA.svg → public/musor-knopka.svg */
const MUSOR_KNOPKA_SRC = "/musor-knopka.svg";

type SiteHeaderProps = {
  /** Landing: GitHub над «H», FAQ над «N» в HUMAN; стиль как в референсе. */
  landingMode?: boolean;
};

export function SiteHeader({ landingMode = false }: SiteHeaderProps) {
  const githubBase = `https://github.com/${defaultRepo}`;

  if (landingMode) {
    return (
      <header className="site-header site-header--imps-landing" role="banner">
        <div className="site-header-landing-stack wrap">
          <div className="site-header-brand-cluster">
            <div className="site-header-wordmark-block">
              <a href="/" className="site-header-human-trance-link" aria-label="VoiceInsert">
                <img
                  className="site-header-human-trance"
                  src={HUMAN_TRANCE_SRC}
                  alt=""
                  width={507}
                  height={212}
                  decoding="async"
                />
              </a>
              <nav className="site-header-nav-over-wordmark" aria-label="Main">
                <a
                  className="site-header-over-mark site-header-over-mark--github"
                  href={githubBase}
                  rel="noopener noreferrer"
                >
                  GitHub
                </a>
                <a className="site-header-over-mark site-header-over-mark--faq" href="/faq">
                  FAQ
                </a>
              </nav>
            </div>
          </div>
          <div className="site-header-wordmark-cta">
            <a
              id="download"
              className="btn-download-solo btn-download-solo--knopka"
              href={macAppZipPath}
              aria-label="Download for Mac"
            >
              <img
                className="btn-download-solo-knopka"
                src={MUSOR_KNOPKA_SRC}
                alt=""
                width={934}
                height={162}
                decoding="async"
              />
            </a>
          </div>
        </div>
      </header>
    );
  }

  return (
    <header className="site-header" role="banner">
      <div className="site-header-inner wrap">
        <a className="site-logo" href="/">
          VoiceInsert
        </a>
        <nav className="site-header-nav-main" aria-label="Main">
          <a className="nav-link" href="/">
            Home
          </a>
          <a className="nav-link" href="/faq">
            FAQ
          </a>
          <a className="nav-link nav-link-cta" href={macAppZipPath}>
            Download
          </a>
          <a className="nav-link nav-link-muted" href={githubBase} rel="noopener noreferrer">
            GitHub
          </a>
        </nav>
      </div>
    </header>
  );
}
