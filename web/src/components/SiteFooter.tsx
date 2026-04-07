const defaultRepo = process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk";

export function SiteFooter() {
  const githubBase = `https://github.com/${defaultRepo}`;
  return (
    <footer className="site-footer wrap">
      <nav className="site-footer-nav" aria-label="Site">
        <a href="/">Home</a>
        <a href="/faq">FAQ</a>
        <a href={githubBase}>GitHub</a>
      </nav>
      <p className="site-footer-meta">
        <a href={githubBase}>GitHub repository</a>
        {" · "}
        MIT License · Not affiliated with Apple Inc.
      </p>
    </footer>
  );
}
