import type { Metadata } from "next";
import { Poppins, Open_Sans } from "next/font/google";
import { LayoutDashboard, Users, FileText } from "lucide-react";
import { ThemeProvider } from "./components/ThemeProvider";
import { ThemeToggle } from "./components/ThemeToggle";
import "./globals.css";

const openSans = Open_Sans({
  variable: "--font-open-sans",
  subsets: ["latin"],
});

const poppins = Poppins({
  variable: "--font-poppins",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

export const metadata: Metadata = {
  title: "Invoice App",
  description: "Manage your clients and invoices seamlessly.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
      <html
        lang="en"
        className={`${openSans.variable} ${poppins.variable}`}
        suppressHydrationWarning
      >
      <body>
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          disableTransitionOnChange
        >
          <div className="app-container">
          <aside className="sidebar">
            <div className="sidebar-logo">InvoiceApp</div>
            <a href="/" className="sidebar-link">
              <LayoutDashboard size={20} style={{ marginRight: 'var(--spacing-3)' }} /> Dashboard
            </a>
            <a href="/clients" className="sidebar-link">
              <Users size={20} style={{ marginRight: 'var(--spacing-3)' }} /> Clients
            </a>
            <a href="/invoices" className="sidebar-link">
              <FileText size={20} style={{ marginRight: 'var(--spacing-3)' }} /> Invoices
            </a>
          </aside>
          <main className="main-content">
            <header className="top-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div className="text-h3" style={{ margin: 0 }}>Workspace</div>
              <ThemeToggle />
            </header>
            <div className="page-content">
              {children}
            </div>
          </main>
          </div>
        </ThemeProvider>
      </body>
    </html>
  );
}
