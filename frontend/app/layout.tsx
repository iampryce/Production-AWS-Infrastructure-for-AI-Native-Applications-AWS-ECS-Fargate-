import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "heartstamp",
  description: "AI-assisted personalized message generation - portfolio demo",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
