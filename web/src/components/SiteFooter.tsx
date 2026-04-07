import { donationPageUrl, macAppZipPath, siteAuthorLinkedInUrl, siteAuthorName } from "@/lib/site";

const defaultRepo = process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk-public";

type SiteFooterProps = {
  /** Landing: hide Home, FAQ, Download (single FAQ in header; one Download on page). */
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
            <a href="/faq">FAQ</a>
            <a href={macAppZipPath}>Download</a>
          </>
        ) : null}
        <a href={githubBase} rel="noopener noreferrer">
          GitHub
        </a>
        <a href={`${githubBase}/releases`} rel="noopener noreferrer">
          Releases
        </a>
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
        <span className="site-footer-note"> (English only)</span>
        <span className="site-footer-sep" aria-hidden="true">
          ·
        </span>
        <span>Free app</span>
        <span className="site-footer-sep" aria-hidden="true">
          ·
        </span>
        <span>Not Apple</span>
      </p>
    </footer>
  );
}
