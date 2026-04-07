import type { Metadata } from "next";
import Link from "next/link";
import { SiteFooter } from "@/components/SiteFooter";
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
      <div className="wrap faq-page">
        <nav className="site-header-nav faq-back" aria-label="Primary">
          <Link href="/">← Home</Link>
        </nav>
        <header className="faq-header">
          <p className="eyebrow">Help & discovery</p>
          <h1>Frequently asked questions</h1>
          <p className="lede faq-intro">
            Quick answers for people searching for <strong>Mac dictation</strong>, <strong>hold-to-talk</strong> apps,{" "}
            <strong>Obsidian voice capture</strong>, and how VoiceInsert compares to built-in options. Updated for
            VoiceInsert on macOS 13+.
          </p>
        </header>

        <section aria-label="Questions and answers">
          <ol className="faq-list">
            {faqItems.map((item, index) => (
              <li key={item.question} className="faq-item">
                <h2 className="faq-question">
                  <span className="faq-number">{index + 1}.</span> {item.question}
                </h2>
                <p className="faq-answer">{item.answer}</p>
              </li>
            ))}
          </ol>
        </section>

        <section className="seo-section faq-cta">
          <h2 className="seo-section-title">Try VoiceInsert</h2>
          <p className="seo-section-lead">
            Download from the <Link href="/">homepage</Link>, review{" "}
            <Link href="/#requirements">system requirements</Link>, or open the{" "}
            <a href={`https://github.com/${process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk"}`}>
              GitHub repository
            </a>{" "}
            for releases and source code.
          </p>
        </section>
      </div>
      <SiteFooter />
    </>
  );
}
