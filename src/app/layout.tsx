import type { Metadata } from 'next';
import './globals.css';
import { AuthProvider } from './AuthProvider';

export const metadata: Metadata = {
  title: 'Luna — Media Hub',
  description: 'A modern media hub powered by the Stremio addon ecosystem',
  icons: {
    icon: [
      { url: '/favicon-16.png', sizes: '16x16', type: 'image/png' },
      { url: '/favicon-32.png', sizes: '32x32', type: 'image/png' },
      { url: '/icon-192.png', sizes: '192x192', type: 'image/png' },
      { url: '/icon-512.png', sizes: '512x512', type: 'image/png' },
    ],
    apple: '/apple-touch-icon.png',
    shortcut: '/favicon.ico',
  },
  openGraph: {
    title: 'Luna — Media Hub',
    description: 'A modern media hub powered by the Stremio addon ecosystem',
    images: [{ url: '/og-image.png', width: 1200, height: 1200 }],
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
      </head>
      <body className="bg-luna-bg text-luna-text antialiased font-sans">
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}
