import { EntryShell } from "@/components/entry-shell";
import { NotFoundMessage } from "@/components/not-found-message";
import { readTheme } from "@/lib/theme-cookie";

// どの画面にも当たらない URL。ルートのレイアウトだけで描かれるので、架空表記を持つ枠をここで包む。行き先はログインの画面
export default async function RootNotFound() {
  return (
    <EntryShell theme={await readTheme()}>
      <NotFoundMessage href="/" label="ログインの画面へ戻る" />
    </EntryShell>
  );
}
