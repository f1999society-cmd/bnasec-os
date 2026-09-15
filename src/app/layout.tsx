import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { Toaster } from "@/components/ui/toaster";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "BNAsec 2.0.0 — Security Testing Live OS",
  description: "Debian 13 (trixie) live security-testing ISO: GNOME desktop, 6 pentest tools, full-root persistence, hybrid BIOS+UEFI boot. Verified in QEMU.",
  keywords: ["BNAsec", "live ISO", "security testing", "pentest", "aircrack-ng", "nmap", "hydra", "wpscan", "dirb", "sqlmap"],
  icons: {
    icon: "/bnasec-logo.png",
  },
  openGraph: {
    title: "BNAsec 2.0.0 — Security Testing Live OS",
    description: "Debian trixie live ISO with full-root persistence and 6 pentest tools",
    siteName: "BNAsec",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased bg-background text-foreground`}
      >
        {children}
        <Toaster />
      </body>
    </html>
  );
}
