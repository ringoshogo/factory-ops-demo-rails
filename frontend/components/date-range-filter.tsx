"use client";

import { CalendarDays } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useId, useState } from "react";
import { FilterButtonLabel, filterButtonClass } from "@/components/filter-bar";
import { DateField } from "@/components/date-field";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Popover, PopoverContent, PopoverTitle, PopoverTrigger } from "@/components/ui/popover";
import { dateRangeLabel, todayInTokyo } from "@/lib/dates";
import { RESET_PAGE } from "@/lib/list";
import { patchHref } from "@/lib/query";

/**
 * 一覧の日付の期間の絞り込み (受注一覧の「受注日」、発注一覧の「発注日」)。
 *
 * ボタンでポップオーバーを開き、開始・終了の日付を入れて「適用」で `from`・`to` を差し替えた URL へ移り、
 * 1 ページ目に戻る。「クリア」は両方を外す。開始が終了より後のときは「適用」を無効にして理由を出し、
 * URL・一覧・タブの件数を変えない。片側だけの指定も適用できる。
 * 開始・終了は DateField (clearable)。日付のカレンダーは自分の Portal に描く入れ子のポップオーバーで、
 * その Esc は日付のカレンダーだけを閉じる。値が無いときの基準の月は業務日付 (得られなければ東京の今日)。
 */
export function DateRangeFilter({
  label,
  from,
  to,
  businessDate,
}: {
  label: string;
  from: string;
  to: string;
  businessDate: string | null;
}) {
  const pathname = usePathname();
  const params = useSearchParams();
  const router = useRouter();
  const id = useId();
  const [open, setOpen] = useState(false);
  // 入れかけの値。開くたびに URL の値から始める
  const [draft, setDraft] = useState({ from, to });
  const invalid = draft.from !== "" && draft.to !== "" && draft.from > draft.to;
  const active = from !== "" || to !== "";
  const reference = businessDate ?? todayInTokyo();

  function onOpenChange(next: boolean) {
    if (next) setDraft({ from, to });
    setOpen(next);
  }

  function apply(patch: { from: string | null; to: string | null }) {
    router.push(patchHref(pathname, params, { ...patch, ...RESET_PAGE }), { scroll: false });
    setOpen(false);
  }

  return (
    <Popover open={open} onOpenChange={onOpenChange}>
      <PopoverTrigger className={filterButtonClass(active)}>
        <FilterButtonLabel
          icon={CalendarDays}
          label={label}
          value={dateRangeLabel(from, to, businessDate)}
          active={active}
        />
      </PopoverTrigger>
      <PopoverContent data-slot="date-range" className="w-80">
        <PopoverTitle className="sr-only">{label}の期間</PopoverTitle>
        <form
          className="space-y-3"
          onSubmit={(e) => {
            e.preventDefault();
            if (!invalid) apply({ from: draft.from || null, to: draft.to || null });
          }}
        >
          {/* 開始・終了は縦に並べる。横に 2 つ並べると 320px の中で「2026年12月28日」が切れる */}
          <div className="grid gap-3">
            {(["from", "to"] as const).map((key) => (
              <div key={key} className="min-w-0 space-y-1.5">
                <Label htmlFor={`${id}-${key}`}>{key === "from" ? "開始" : "終了"}</Label>
                <DateField
                  id={`${id}-${key}`}
                  name={key}
                  value={draft[key]}
                  onChange={(iso) => setDraft((d) => ({ ...d, [key]: iso }))}
                  referenceDate={reference}
                  clearable
                />
              </div>
            ))}
          </div>
          <p role="status" className="text-destructive text-[13px]">
            {invalid ? "開始日は終了日以前にしてください" : ""}
          </p>
          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={() => apply({ from: null, to: null })}>
              クリア
            </Button>
            <Button type="submit" disabled={invalid}>
              適用
            </Button>
          </div>
        </form>
      </PopoverContent>
    </Popover>
  );
}
