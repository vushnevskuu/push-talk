import Link from "next/link";
import { macAppZipPath, donationPageUrl } from "@/lib/site";

const defaultRepo = process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk-public";

export default function SuccessPage() {
  const githubBase = `https://github.com/${defaultRepo}`;
  const donate = donationPageUrl();

  return (
    <div className="wrap page-simple">
      <header className="page-simple-header">
        <p className="eyebrow">VoiceInsert</p>
        <h1>This page is no longer used for billing</h1>
        <p className="lede page-simple-lede">
          VoiceInsert is distributed as a <strong>free</strong> Mac app. There is no checkout or access token step. If you
          landed here from an old link or bookmark, use the download below.
        </p>

        <div className="card success-download" aria-label="Download Mac app">
          <h2 className="claim-card-title">Download for Mac</h2>
          <p className="path-card-desc">
            Official ZIP from this site (same file as on the homepage). Unzip, drag VoiceInsert.app to Applications, launch
            once.
          </p>
          <div className="cta-row path-card-cta">
            <a className="btn-primary" href={macAppZipPath}>
              Download for Mac (ZIP)
            </a>
            <a className="btn-secondary" href={`${githubBase}/releases`} rel="noopener noreferrer">
              GitHub releases
            </a>
            {donate ? (
              <a className="btn-secondary" href={donate} rel="noopener noreferrer">
                Support the project
              </a>
            ) : null}
          </div>
        </div>

        <p className="page-simple-footer-link">
          <Link href="/">← Back to home</Link>
        </p>
      </header>
    </div>
  );
}
