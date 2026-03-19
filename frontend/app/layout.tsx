import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { Providers } from "./providers";

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});

const BASE_URL = process.env.NEXT_PUBLIC_BASE_URL ?? "https://stablestream.xyz";

export const metadata: Metadata = {
  metadataBase: new URL(BASE_URL),
  title: {
    default: "StableStream: Yield Without Limits",
    template: "%s | StableStream",
  },
  description:
    "StableStream is a Uniswap v4 hook that autonomously routes out-of-range liquidity into yield sources. Maximising capital efficiency without lifting a finger.",
  keywords: ["DeFi", "Uniswap v4", "liquidity", "yield", "hook", "Unichain", "StableStream", "concentrated liquidity", "AMM"],
  authors: [{ name: "StableStream" }],
  creator: "StableStream",
  openGraph: {
    title: "StableStream: Yield Without Limits",
    description:
      "Autonomous yield routing for Uniswap v4 concentrated liquidity. Built for the Uniswap v4 Hookathon on Unichain Sepolia.",
    url: BASE_URL,
    siteName: "StableStream",
    images: [
      {
        url: "/logo-wordmark.png",
        width: 1800,
        height: 360,
        alt: "StableStream: Yield Without Limits",
        type: "image/png",
      },
    ],
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    site: "@StableStream",
    creator: "@StableStream",
    title: "StableStream: Yield Without Limits",
    description:
      "Autonomous yield routing for Uniswap v4 concentrated liquidity. Built for the Uniswap v4 Hookathon.",
    images: [
      {
        url: "/logo-wordmark.png",
        alt: "StableStream — Yield Without Limits",
      },
    ],
  },
  icons: {
    icon: [
      { url: "/logo.svg", type: "image/svg+xml" },
      { url: "/logo.png", sizes: "512x512", type: "image/png" },
    ],
    apple: "/logo.png",
  },
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true },
  },
  category: "finance",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={inter.variable}>
      <body className="antialiased">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
