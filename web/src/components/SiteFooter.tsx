import {
  donationPageUrl,
  macAppZipPath,
  siteAuthorLinkedInUrl,
  siteAuthorName,
  siteAuthorPortfolioUrl,
} from "@/lib/site";

const defaultRepo = process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk";

type SiteFooterProps = {
  /** Landing: “How it works” + optional donate; full nav when not landing. */
  landingMode?: boolean;
};

export function SiteFooter({ landingMode = false }: SiteFooterProps) {
  const githubBase = `https://github.com/${defaultRepo}`;
  const name = siteAuthorName();
  const portfolio = siteAuthorPortfolioUrl();
  const linkedIn = siteAuthorLinkedInUrl();
  const donate = donationPageUrl();

  return (
    <footer className="site-footer wrap">
      <nav className="site-footer-nav" aria-label="Site">
        {!landingMode ? (
          <>
            <a href="/">Home</a>
            <a href="/demo.html">How it works</a>
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
          <a href="/demo.html">How it works</a>
        )}
        {donate ? (
          <a href={donate} rel="noopener noreferrer">
            Buy me a coffee
          </a>
        ) : null}
      </nav>
      <p className="site-footer-compact">
        <a href={portfolio} rel="noopener noreferrer" target="_blank" aria-label={`${name} — portfolio`}>
          {name}
        </a>
        <span className="site-footer-open-to-work"> · Open to work</span>
        <span className="site-footer-sep" aria-hidden="true">
          ·
        </span>
        <a href={linkedIn} rel="noopener noreferrer" target="_blank" aria-label={`${name} on LinkedIn`}>
          LinkedIn
        </a>
      </p>
    </footer>
  );
}
