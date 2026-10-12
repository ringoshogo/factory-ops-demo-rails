"use client";

import { usePathname, useSearchParams } from "next/navigation";
import { LinkTabs } from "@/components/link-tabs";
import { RESET_PAGE } from "@/lib/list";
import { patchHref } from "@/lib/query";

/**
 * 一覧のタブ。リンクは描くときの URL に、タブの差し替えを当てて作る。タブを押すと状況の絞り込みを外し、1 ページ目に戻る。
 * `counts` が無い (API の失敗) ときは札を出さない。
 */
export function ListTabs<T extends string>({
  label,
  tabs,
  current,
  counts,
}: {
  label: string;
  tabs: readonly { tab: T; label: string }[];
  current: T;
  counts: Record<T, number> | null;
}) {
  const pathname = usePathname();
  const params = useSearchParams();
  return (
    <LinkTabs
      label={label}
      tabs={tabs.map(({ tab, label: text }, i) => ({
        href: patchHref(pathname, params, { tab: i === 0 ? null : tab, status: null, ...RESET_PAGE }),
        label: text,
        current: tab === current,
        count: counts?.[tab],
      }))}
    />
  );
}
