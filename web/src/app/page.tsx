import type { Metadata, Viewport } from "next";
import { JsonLd } from "@/components/JsonLd";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import {
  macAppZipAbsoluteUrl,
  siteAuthorLinkedInUrl,
  siteAuthorName,
  siteDescription,
  siteOgImagePath,
  siteOgImageSize,
  siteOrigin,
} from "@/lib/site";
import HomeClient from "./HomeClient";

const description = siteDescription;

export const metadata: Metadata = {
  description,
  keywords: [
    "VoiceInsert",
    "macOS dictation",
    "hold to talk dictation",
    "menu bar dictation",
    "Obsidian voice notes",
    "dictation app Mac",
    "push to talk Mac",
    "speech to text Mac",
    "global dictation shortcut",
    "on-device dictation",
    "VoiceInsert download",
  ],
  alternates: {
    canonical: "/",
  },
  openGraph: {
    title: "VoiceInsert — Hold-to-talk dictation for Mac",
    description,
    url: "/",
    images: [
      {
        url: siteOgImagePath,
        width: siteOgImageSize.width,
        height: siteOgImageSize.height,
        alt: "VoiceInsert — hold-to-talk dictation for macOS",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "VoiceInsert — Hold-to-talk dictation for Mac",
    description,
    images: [siteOgImagePath],
  },
};

export const viewport: Viewport = {
  themeColor: "#ffffff",
};

export default function HomePage() {
  const origin = siteOrigin();
  const repo = process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk-public";
  const github = `https://github.com/${repo}`;

  const softwareJsonLd = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "VoiceInsert",
    applicationCategory: "UtilitiesApplication",
    operatingSystem: "macOS",
    operatingSystemVersion: "macOS 13 or later",
    description,
    url: origin,
    downloadUrl: macAppZipAbsoluteUrl(),
    softwareHelp: `${origin}/faq`,
    isAccessibleForFree: true,
    offers: {
      "@type": "Offer",
      price: "0",
      priceCurrency: "USD",
      availability: "https://schema.org/InStock",
      url: macAppZipAbsoluteUrl(),
    },
    author: {
      "@type": "Person",
      name: siteAuthorName(),
      url: siteAuthorLinkedInUrl(),
    },
    publisher: {
      "@type": "Organization",
      name: "VoiceInsert",
      url: origin,
      sameAs: [github],
    },
    featureList: [
      "Hold-to-talk global dictation shortcut",
      "Inserts transcribed text into the focused application",
      "Optional Obsidian vault Markdown capture",
      "On-device speech recognition via Apple Speech framework",
    ],
  };

  const websiteJsonLd = {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: "VoiceInsert",
    url: origin,
    description,
    inLanguage: "en-US",
    publisher: {
      "@type": "Organization",
      name: "VoiceInsert",
      url: origin,
      sameAs: [github],
    },
  };

  return (
    <>
      <JsonLd data={[softwareJsonLd, websiteJsonLd]} />
      <div className="page-whispering-imps">
        <SiteHeader landingMode />
        <HomeClient />
        <SiteFooter landingMode />
      </div>
    </>
  );
}
