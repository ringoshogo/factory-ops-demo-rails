import { cn } from "cn";
import { PageFrame } from "@/components/page-frame";
import { ThemeToggle } from "@/components/theme-toggle";
import type { ThemeChoice } from "@/lib/theme";

/**
 * ログインの画面と、どの画面にも当たらない URL の枠。ログインするまで行き先が無いので、ナビゲーションを持たない。
 * 業務の画面と同じパネルに載せ、テーマの切り替えはパネルの上の台に置く。
 */
export function EntryShell({ theme, children }: { theme: ThemeChoice; children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen w-full">
      <PageFrame
        top={
          <div className="flex justify-end px-3 pt-2">
            <ThemeToggle initial={theme} />
          </div>
        }
      >
        <main className="flex w-full min-w-0 flex-1 items-start justify-center py-6 sm:items-center">
          <div className="w-full max-w-md">{children}</div>
        </main>
      </PageFrame>
    </div>
  );
}

/**
 * ログインの画面と見つからない画面の本文を載せるカード。パネルの上に浮いた面 (--surface-raised・--shadow-card・
 * rounded-card。かんばんのカードと同じ段) を 1 枚置く。見つからない画面はサイドバーの枠の中でも同じカードを使う。
 */
export function EntryCard({ className, ...props }: React.ComponentProps<"section">) {
  return <section className={cn("bg-surface-raised shadow-card rounded-card p-8", className)} {...props} />;
}
