import type { Metadata, Viewport } from "next";
import Link from "next/link";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import { JsonLd } from "@/components/JsonLd";
import { siteOgImagePath, siteOgImageSize, siteOrigin } from "@/lib/site";
import { faqItems } from "./faq-data";

const MUSOR_BULLET_SRC = "/musor-bullet.svg";

const title = "FAQ — VoiceInsert Mac dictation, Obsidian, permissions & privacy";
const description =
  "Answers about VoiceInsert: hold-to-talk dictation on macOS, Obsidian voice notes, Apple Dictation comparison, Cursor/IDE support, permissions, privacy, offline use, Gatekeeper, and pricing.";

export const metadata: Metadata = {
  title,
  description,
  keywords: [
    "VoiceInsert FAQ",
    "macOS dictation app",
    "hold to talk dictation",
    "Obsidian voice notes",
    "dictate into Cursor",
    "menu bar dictation Mac",
    "Apple Dictation alternative",
    "push to talk transcription",
    "on-device speech recognition Mac",
    "VoiceInsert permissions",
  ],
  alternates: {
    canonical: "/faq",
  },
  openGraph: {
    title,
    description,
    type: "article",
    url: "/faq",
    images: [
      {
        url: siteOgImagePath,
        width: siteOgImageSize.width,
        height: siteOgImageSize.height,
        alt: "VoiceInsert — Mac dictation FAQ",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title,
    description,
    images: [siteOgImagePath],
  },
};

export const viewport: Viewport = {
  themeColor: "#ffffff",
};

function FaqImpDivider() {
  return (
    <div className="imp-divider" aria-hidden="true">
      <img
        className="imp-divider-svecha"
        src="/svecha.svg"
        alt=""
        width={25}
        height={60}
        decoding="async"
      />
    </div>
  );
}

export default function FaqPage() {
  const origin = siteOrigin();
  const faqJsonLd = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: faqItems.map((item) => ({
      "@type": "Question",
      name: item.question,
      acceptedAnswer: {
        "@type": "Answer",
        text: item.answer,
      },
    })),
  };

  const breadcrumbJsonLd = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      { "@type": "ListItem", position: 1, name: "Home", item: `${origin}/` },
      { "@type": "ListItem", position: 2, name: "FAQ", item: `${origin}/faq` },
    ],
  };

  return (
    <>
      <JsonLd data={[faqJsonLd, breadcrumbJsonLd]} />
      <div className="page-whispering-imps">
        <SiteHeader landingMode />
        <div className="wrap landing-onpage landing-whisper imp-parchment-wrap faq-page">
          <header className="faq-header landing-reveal imp-hero-card" aria-labelledby="faq-page-title">
            <p className="eyebrow">Help & discovery</p>
            <h1 id="faq-page-title" className="landing-h2 faq-visual-title">
              Frequently asked questions
            </h1>
            <p className="lede faq-intro landing-lede">
              Quick answers about <strong className="landing-strong">Mac dictation</strong>,{" "}
              <strong className="landing-strong">hold-to-talk</strong>,{" "}
              <strong className="landing-strong">Obsidian voice capture</strong>, and how VoiceInsert differs from
              built-in dictation. For macOS 13+.
            </p>
            <p className="faq-hint">
              Expand each question below (click, tap, or Enter/Space on the summary). Full text stays in the page for
              search and assistive tech.
            </p>
          </header>

          <FaqImpDivider />

          <section
            aria-label="Questions and answers"
            className="faq-accordion-section landing-reveal landing-reveal-delay-1"
          >
            {faqItems.map((item) => (
              <details key={item.question} className="faq-details">
                <summary className="faq-summary">
                  <span className="faq-summary-mark" aria-hidden="true">
                    <img
                      className="faq-summary-bullet"
                      src={MUSOR_BULLET_SRC}
                      alt=""
                      width={96}
                      height={76}
                      decoding="async"
                    />
                  </span>
                  <span className="faq-summary-text">{item.question}</span>
                </summary>
                <div className="faq-panel">
                  <p className="faq-answer">{item.answer}</p>
                </div>
              </details>
            ))}
          </section>

          <FaqImpDivider />

          <section
            className="faq-cta landing-details landing-reveal landing-reveal-delay-2"
            aria-labelledby="faq-cta-heading"
          >
            <h2 id="faq-cta-heading" className="landing-h2">
              Try VoiceInsert
            </h2>
            <p className="landing-prose landing-prose-tight faq-cta-lede">
              Download from the <Link href="/#download">homepage</Link>, review{" "}
              <Link href="/#requirements">system requirements</Link>, or open the{" "}
              <a href={`https://github.com/${process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk-public"}`}>
                public GitHub repository
              </a>{" "}
              for Mac builds and release notes (application source is not published there).
            </p>
          </section>
        </div>
        <SiteFooter landingMode />
      </div>
    </>
  );
}
