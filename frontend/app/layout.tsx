import type { Metadata } from "next";
import { Space_Grotesk, IBM_Plex_Sans, IBM_Plex_Mono } from "next/font/google";
import "./globals.css";
import { Providers } from "./providers";

const spaceGrotesk = Space_Grotesk({
  subsets: ["latin"],
  variable: "--font-display",
  display: "swap",
});

const ibmPlexSans = IBM_Plex_Sans({
  subsets: ["latin"],
  weight: ["400", "600", "700"],
  variable: "--font-body",
  display: "swap",
});

const ibmPlexMono = IBM_Plex_Mono({
  subsets: ["latin"],
  weight: ["400", "600", "700"],
  variable: "--font-mono",
  display: "swap",
});

const BASE_URL = process.env.NEXT_PUBLIC_BASE_URL ?? "https://stablestream.online";

export const metadata: Metadata = {
  metadataBase: new URL(BASE_URL),
  title: {
    default: "StableStream: Reactive Yield Automation for Uniswap v4",
    template: "%s | StableStream",
  },
  description:
    "StableStream is a Uniswap v4 hook that autonomously routes out-of-range liquidity into yield sources — automated by Reactive Network, triggered by on-chain events. Same-block yield routing, zero off-chain infrastructure.",
  keywords: ["DeFi", "Uniswap v4", "liquidity", "yield", "hook", "Unichain", "StableStream", "concentrated liquidity", "AMM", "Reactive Network", "automation"],
  authors: [{ name: "StableStream" }],
  creator: "StableStream",
  openGraph: {
    title: "StableStream: Reactive Yield Automation",
    description:
      "Reactive yield automation for Uniswap v4. Out-of-range USDC earns Compound yield — recalled just-in-time by a Reactive Network RSC.",
    url: BASE_URL,
    siteName: "StableStream",
    images: [
      {
        url: "/logo-wordmark.png",
        width: 1800,
        height: 360,
        alt: "StableStream: Reactive Yield Automation",
        type: "image/png",
      },
    ],
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    site: "@HQstablestream",
    creator: "@HQstablestream",
    title: "StableStream: Reactive Yield Automation",
    description:
      "Reactive yield automation for Uniswap v4. Out-of-range USDC earns Compound yield — recalled just-in-time by a Reactive Network RSC.",
    images: [
      {
        url: "/logo-wordmark.png",
        alt: "StableStream — Reactive Yield Automation",
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
    <html lang="en" className={`${spaceGrotesk.variable} ${ibmPlexSans.variable} ${ibmPlexMono.variable}`}>
      <body className="antialiased">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
