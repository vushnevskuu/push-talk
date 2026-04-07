import type { Metadata } from "next";

export const metadata: Metadata = {
  robots: { index: false, follow: false },
  title: "Checkout complete",
};

export default function SuccessLayout({ children }: { children: React.ReactNode }) {
  return children;
}
