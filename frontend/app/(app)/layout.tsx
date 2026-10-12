import { AppShell } from "@/components/app-shell";
import { readTheme } from "@/lib/theme-cookie";
import { loadViewer } from "@/lib/viewer";

// ログインした後の画面。サイドバーを持つ
export default async function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <AppShell viewer={await loadViewer()} theme={await readTheme()}>
      {children}
    </AppShell>
  );
}
