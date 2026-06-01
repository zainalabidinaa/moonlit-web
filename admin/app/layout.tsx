import type { Metadata } from 'next';
import './globals.css';
import { AdminAuthProvider } from '../components/AdminAuthProvider';

export const metadata: Metadata = { title: 'Luna Admin', description: 'Luna administration panel' };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
      </head>
      <body><AdminAuthProvider>{children}</AdminAuthProvider></body>
    </html>
  );
}
