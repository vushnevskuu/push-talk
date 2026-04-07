import type { Metadata, Viewport } from "next";
import Script from "next/script";
import { getSiteUrl, siteDescription, siteOgImagePath, siteOgImageSize } from "@/lib/site";
import "./globals.css";

const siteUrl = getSiteUrl();

export const metadata: Metadata = {
  metadataBase: siteUrl,
  title: {
    default: "VoiceInsert — Hold-to-talk dictation for Mac",
    template: "%s | VoiceInsert",
  },
  description: siteDescription,
  applicationName: "VoiceInsert",
  authors: [{ name: "VoiceInsert", url: siteUrl.origin }],
  creator: "VoiceInsert",
  formatDetection: {
    email: false,
    address: false,
    telephone: false,
  },
  openGraph: {
    type: "website",
    siteName: "VoiceInsert",
    locale: "en_US",
    title: "VoiceInsert — Hold-to-talk dictation for Mac",
    description: siteDescription,
    url: siteUrl.origin,
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
    description: siteDescription,
    images: [siteOgImagePath],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-video-preview": -1,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
  verification: process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION
    ? { google: process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION }
    : undefined,
};

export const viewport: Viewport = {
  themeColor: "#0e0b09",
  width: "device-width",
  initialScale: 1,
};

const gaId = process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          href="https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,400;0,9..40,500;0,9..40,600;0,9..40,700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>
        <a className="skip-link" href="#main-content">
          Skip to content
        </a>
        {gaId ? (
          <>
            <Script src={`https://www.googletagmanager.com/gtag/js?id=${gaId}`} strategy="afterInteractive" />
            <Script id="ga4-init" strategy="afterInteractive">
              {`
                window.dataLayer = window.dataLayer || [];
                function gtag(){dataLayer.push(arguments);}
                gtag('js', new Date());
                gtag('config', '${gaId}');
              `}
            </Script>
          </>
        ) : null}
        <main id="main-content" tabIndex={-1}>
          {children}
        </main>
      </body>
    </html>
  );
}
