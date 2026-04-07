import type { Metadata } from "next";

export const metadata: Metadata = {
  robots: { index: false, follow: false },
  title: "Access",
};

export default function GateLayout({ children }: { children: React.ReactNode }) {
  return children;
}
