const defaultRepo = process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk-public";

export function SiteHeader() {
  const githubBase = `https://github.com/${defaultRepo}`;
  const zipUrl = `${githubBase}/releases/latest/download/VoiceInsert-macos.zip`;

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
          <a className="nav-link nav-link-cta" href={zipUrl}>
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
