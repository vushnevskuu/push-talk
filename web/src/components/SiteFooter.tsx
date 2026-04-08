import { donationPageUrl, macAppZipPath, siteAuthorLinkedInUrl, siteAuthorName } from "@/lib/site";

const defaultRepo = process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk";

type SiteFooterProps = {
  /** Landing: ссылка «Как это работает» + опциональный donate; полные ссылки — вне landing. */
  landingMode?: boolean;
};

export function SiteFooter({ landingMode = false }: SiteFooterProps) {
  const githubBase = `https://github.com/${defaultRepo}`;
  const name = siteAuthorName();
  const linkedIn = siteAuthorLinkedInUrl();
  const donate = donationPageUrl();

  return (
    <footer className="site-footer wrap">
      <nav className="site-footer-nav" aria-label="Site">
        {!landingMode ? (
          <>
            <a href="/">Home</a>
            <a href="/demo.html">Как это работает</a>
            <a href="/faq">FAQ</a>
            <a href={macAppZipPath}>Download</a>
            <a href={githubBase} rel="noopener noreferrer">
              GitHub
            </a>
            <a href={`${githubBase}/releases`} rel="noopener noreferrer">
              Releases
            </a>
          </>
        ) : (
          <a href="/demo.html">Как это работает</a>
        )}
        {donate ? (
          <a href={donate} rel="noopener noreferrer">
            Buy me a coffee
          </a>
        ) : null}
      </nav>
      <p className="site-footer-compact">
        <a href={linkedIn} rel="noopener noreferrer" target="_blank" aria-label={`${name} on LinkedIn`}>
          {name}
        </a>
        <span className="site-footer-sep" aria-hidden="true">
          ·
        </span>
        <a href={linkedIn} rel="noopener noreferrer" target="_blank">
          LinkedIn
        </a>
      </p>
    </footer>
  );
}
