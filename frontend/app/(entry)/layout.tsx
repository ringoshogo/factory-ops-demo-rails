import { EntryShell } from "@/components/entry-shell";
import { readTheme } from "@/lib/theme-cookie";

// ログインの画面。サイドバーとメニューのボタンを出さない
export default async function EntryLayout({ children }: { children: React.ReactNode }) {
  return <EntryShell theme={await readTheme()}>{children}</EntryShell>;
}
