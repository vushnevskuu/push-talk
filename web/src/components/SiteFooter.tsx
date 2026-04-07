import { siteAuthorLinkedInUrl, siteAuthorName } from "@/lib/site";

const defaultRepo = process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk-public";

export function SiteFooter() {
  const githubBase = `https://github.com/${defaultRepo}`;
  const authorName = siteAuthorName();
  const authorLinkedIn = siteAuthorLinkedInUrl();
  return (
    <footer className="site-footer wrap">
      <nav className="site-footer-nav" aria-label="Site">
        <a href="/">Home</a>
        <a href="/faq">FAQ</a>
        <a href={githubBase}>GitHub</a>
      </nav>
      <p className="site-footer-author">
        Made by{" "}
        <a
          href={authorLinkedIn}
          rel="noopener noreferrer"
          target="_blank"
          aria-label={`${authorName} on LinkedIn`}
        >
          {authorName}
        </a>
      </p>
      <p className="site-footer-meta">
        <a href={githubBase}>GitHub releases</a>
        {" · "}
        Official Mac builds use subscription billing · Not affiliated with Apple Inc.
      </p>
    </footer>
  );
}
