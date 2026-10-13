"use client";

import { cn } from "cn";
import { Link } from "@/components/app-link";

export type LinkTab = {
  href: string;
  label: string;
  current: boolean;
  /** 札に出す件数。無ければ札を出さない (在庫のタブ・API の失敗時)。 */
  count?: number;
};

/**
 * URL を変えるリンクのタブ。
 *
 * 名前つきのナビゲーションにリンクを並べ、選択中は `aria-current="page"`。並びの下の --divider の
 * 線が見出しの区切りを兼ねる (タブを置く画面の見出しは線を引かない)。選択中の
 * --primary の 2px の下線は、`-mb-px` でその線の上に重ねる。
 *
 * 狭い幅ではタブの並びだけが横にスクロールする。Tab キーで移ったタブが端で切れたままにならないよう、
 * フォーカスを受けたタブを並びの中で見える位置まで送る (ブラウザは一部が見えている要素を送らない)。
 */
export function LinkTabs({ label, tabs }: { label: string; tabs: LinkTab[] }) {
  return (
    <nav
      aria-label={label}
      className="border-divider flex gap-6 overflow-x-auto border-b"
      onFocus={(e) => e.target.scrollIntoView({ block: "nearest", inline: "nearest" })}
    >
      {tabs.map((tab) => (
        <Link
          key={tab.href}
          href={tab.href}
          aria-current={tab.current ? "page" : undefined}
          className={cn(
            "-mb-px flex shrink-0 items-center gap-2 rounded-sm border-b-2 px-0.5 pb-2.5 font-medium whitespace-nowrap",
            tab.current
              ? "border-primary text-foreground"
              : "text-muted-foreground hover:text-foreground border-transparent",
          )}
        >
          <span>{tab.label}</span>
          {tab.count !== undefined && (
            <span
              data-testid="tab-count"
              className={cn(
                "rounded-[9999px] px-[7px] text-xs tabular-nums",
                tab.current ? "bg-filter-active text-link" : "bg-background text-muted-foreground",
              )}
            >
              {tab.count}
            </span>
          )}
        </Link>
      ))}
    </nav>
  );
}
