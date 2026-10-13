"use client";

import { ArrowDown, ArrowUp, ChevronsUpDown } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { SORT_ICON, TableHead } from "@/components/ui/table";
import { nextSort, sortHref, type Sort } from "@/lib/list";

/**
 * 並べ替えの見出し。押すたびに 昇順 → 降順 → 既定の並び。サーバーで並べるので、URL を変えて描き直させ、1 ページ目に戻す。
 * ボタンの名前は見出しの文字そのものにする (`aria-label` を付けると、同じ文字の入力欄のラベルの検索に見出しも当たる)。
 */
export function SortableHead<F extends string>({
  label,
  field,
  state,
  numeric = false,
}: {
  label: string;
  field: F;
  state: Sort<F>;
  numeric?: boolean;
}) {
  const pathname = usePathname();
  const params = useSearchParams();
  const router = useRouter();
  const dir = state?.field === field ? state.direction : null;
  const Icon = dir === "ASC" ? ArrowUp : dir === "DESC" ? ArrowDown : ChevronsUpDown;

  return (
    <TableHead aria-sort={dir === "ASC" ? "ascending" : dir === "DESC" ? "descending" : undefined} numeric={numeric}>
      {/* 矢印はどの列も文字の右。数値の列のセルは矢印の幅を空けて、数字を文字の右端にそろえる */}
      <button
        type="button"
        onClick={() => router.replace(sortHref(pathname, params, nextSort(state, field)), { scroll: false })}
        className={`hover:text-foreground inline-flex items-center ${SORT_ICON.gap} rounded-sm ${dir ? "text-foreground" : ""}`}
      >
        {label}
        <Icon aria-hidden className={`${SORT_ICON.size} shrink-0 ${dir ? "" : "text-muted-foreground"}`} />
      </button>
    </TableHead>
  );
}
