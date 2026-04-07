import type { Metadata } from "next";
import Link from "next/link";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import { JsonLd } from "@/components/JsonLd";
import { siteOrigin } from "@/lib/site";
import { faqItems } from "./faq-data";

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
  },
  twitter: {
    card: "summary_large_image",
    title,
    description,
  },
};

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
      <SiteHeader />
      <div className="wrap faq-page">
        <header className="faq-header">
          <p className="eyebrow">Help & discovery</p>
          <h1>Frequently asked questions</h1>
          <p className="lede faq-intro">
            Quick answers about <strong>Mac dictation</strong>, <strong>hold-to-talk</strong>,{" "}
            <strong>Obsidian voice capture</strong>, and how VoiceInsert differs from built-in dictation. For macOS 13+.
          </p>
          <p className="faq-hint">
            Expand each question below (click, tap, or Enter/Space on the summary). Full text stays in the page for search
            and assistive tech.
          </p>
        </header>

        <section aria-label="Questions and answers" className="faq-accordion-section">
          {faqItems.map((item, index) => (
            <details key={item.question} className="faq-details">
              <summary className="faq-summary">
                <span className="faq-summary-num" aria-hidden="true">
                  {String(index + 1).padStart(2, "0")}
                </span>
                <span className="faq-summary-text">{item.question}</span>
              </summary>
              <div className="faq-panel">
                <p className="faq-answer">{item.answer}</p>
              </div>
            </details>
          ))}
        </section>

        <section className="seo-section faq-cta">
          <h2 className="seo-section-title">Try VoiceInsert</h2>
          <p className="seo-section-lead">
            Download from the <Link href="/#download">homepage</Link>, review{" "}
            <Link href="/#requirements">system requirements</Link>, or open the{" "}
            <a href={`https://github.com/${process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk-public"}`}>
              public GitHub repository
            </a>{" "}
            for Mac builds and release notes (application source is not published there).
          </p>
        </section>
      </div>
      <SiteFooter />
    </>
  );
}
