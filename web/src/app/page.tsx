import type { Metadata } from "next";
import { JsonLd } from "@/components/JsonLd";
import { SiteFooter } from "@/components/SiteFooter";
import { siteOrigin } from "@/lib/site";
import HomeClient from "./HomeClient";

const description =
  "VoiceInsert: hold-to-talk dictation for Mac. Insert speech into any focused app or save voice notes to Obsidian. Menu bar app, on-device recognition, macOS 13+. FAQ, download, GitHub.";

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
  },
  twitter: {
    card: "summary_large_image",
    title: "VoiceInsert — Hold-to-talk dictation for Mac",
    description,
  },
};

export default function HomePage() {
  const origin = siteOrigin();
  const repo = process.env.NEXT_PUBLIC_GITHUB_REPO ?? "vushnevskuu/push-talk";
  const github = `https://github.com/${repo}`;

  const softwareJsonLd = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "VoiceInsert",
    applicationCategory: "UtilitiesApplication",
    operatingSystem: "macOS 13+",
    description,
    url: origin,
    downloadUrl: `${github}/releases/latest/download/VoiceInsert-macos.zip`,
    license: `${github}/blob/main/LICENSE`,
    isAccessibleForFree: true,
    publisher: {
      "@type": "Organization",
      name: "VoiceInsert",
      url: origin,
    },
    sameAs: [github],
  };

  const websiteJsonLd = {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: "VoiceInsert",
    url: origin,
    description,
    inLanguage: "en-US",
  };

  return (
    <>
      <JsonLd data={[softwareJsonLd, websiteJsonLd]} />
      <HomeClient />
      <SiteFooter />
    </>
  );
}
