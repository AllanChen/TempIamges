import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Glance — Widget Market',
  description: 'Focused cloud tools for the media you preview in Glance.',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en"><body>{children}</body>
    </html>
  );
}
