"use client";

import { ArrowDown, ArrowUp, ChevronsUpDown } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { SORT_ICON, TableHead } from "@/components/ui/table";
import { nextSort, sortHref, sortRank, type Sort } from "@/lib/list";

/**
 * 並べ替えの見出し。押すとその列 1 つの並びにし (同じ列は 昇順 → 降順 → 既定の並び)、Shift を押して押すと 2 つ目からの並べる列を
 * 足す (`nextSort`)。サーバーで並べるので、URL を変えて描き直させ、1 ページ目に戻す。
 * ボタンの名前は見出しの文字そのものにする (`aria-label` を付けると、同じ文字の入力欄のラベルの検索に見出しも当たる)。
 * 並びが 2 つ以上なら、矢印の右に何番目の並べる列かの番号を出す。`aria-sort` は WAI-ARIA 1.2 が 1 度に 1 つの見出しにだけ
 * 付けるよう求めるので 1 つ目の列にだけ付け、2 つ目からの列は順番と向きを見えない文字でボタンの外に添える。
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
  const index = state.findIndex((s) => s.field === field);
  const dir = state[index]?.direction ?? null;
  const rank = sortRank(state, field);
  const Icon = dir === "ASC" ? ArrowUp : dir === "DESC" ? ArrowDown : ChevronsUpDown;

  return (
    <TableHead aria-sort={index === 0 ? (dir === "ASC" ? "ascending" : "descending") : undefined} numeric={numeric}>
      {/* 矢印と番号はどの列も文字の右。数値の列のセルは矢印と番号の幅を空けて、数字を文字の右端にそろえる */}
      <button
        type="button"
        // ブラウザは Shift を押したクリックで、前のクリックの位置からの文字を選ぶので、その既定の動きだけを止める。
        // Shift を押さないクリックは止めず、いまと同じくボタンにフォーカスが移る
        onMouseDown={(e) => {
          if (e.shiftKey) e.preventDefault();
        }}
        onClick={(e) => router.replace(sortHref(pathname, params, nextSort(state, field, e.shiftKey)), { scroll: false })}
        className={`hover:text-foreground inline-flex items-center ${SORT_ICON.gap} rounded-sm ${dir ? "text-foreground" : ""}`}
      >
        {label}
        <Icon aria-hidden className={`${SORT_ICON.size} shrink-0 ${dir ? "" : "text-muted-foreground"}`} />
        {rank && (
          <span aria-hidden data-sort-rank={rank} className={`${SORT_ICON.rank} shrink-0`}>
            {rank}
          </span>
        )}
      </button>
      {rank && rank > 1 && <span className="sr-only">{`並べ替え ${rank} 番目・${dir === "ASC" ? "昇順" : "降順"}`}</span>}
    </TableHead>
  );
}
