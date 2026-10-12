"use client";

import { CalendarDays } from "lucide-react";
import { cn } from "cn";
import { useRef, useState } from "react";
import { Calendar } from "@/components/ui/calendar";
import { CONTROL_SURFACE } from "@/components/ui/input";
import { Popover, PopoverContent, PopoverTitle, PopoverTrigger } from "@/components/ui/popover";
import { isIsoDate } from "@/lib/calendar";
import { formatFullDate } from "@/lib/dates";

/**
 * 日付の入力 (仕様 cycle-03 §5)。「2026年10月8日」と書かれたボタンでカレンダーを開いて選ぶ。
 * ブラウザ既定の日付の入力 (mm/dd/yyyy) は使わない。
 *
 * - 送る値は `name` の隠し入力の YYYY-MM-DD。既定値 (受注登録 = 今日・出荷予定日 = 希望納期) は
 *   `defaultValue` でそのまま渡す。期間の絞り込みでは親が `value`・`onChange` で値を持つ
 * - 項目名は外の `<label htmlFor={id}>` で付ける (ボタンが label の名前を持つ)。label の名前は中身の文字を
 *   含まないので、表示中の値 (未入力なら「日付を選ぶ」) は `aria-describedby` で説明として読ませる
 * - ポップオーバーは modal (フォーカスを中に閉じ込める。閉じ込めには中の Popover.Close が要る)。
 *   Popover.Popup は aria-modal を付けないので明示する。名前は「日付を選ぶ」
 * - 開くと選んでいる日 (無ければ基準の日) にフォーカスし、閉じるとフォーカスはボタンへ戻る (Base UI の既定)
 * - 業務の検証 (必須・日付の前後) はしない。API の結果をそのまま出す
 */
export function DateField({
  id,
  name,
  defaultValue,
  value,
  onChange,
  referenceDate,
  clearable = false,
  disabled = false,
  className,
}: {
  id: string;
  name?: string;
  defaultValue?: string;
  value?: string;
  onChange?: (iso: string) => void;
  /** 値が無いとき最初に見せる月 (業務日付か今日) */
  referenceDate: string;
  /** 絞り込みだけ true。「日付を消す」を出す */
  clearable?: boolean;
  disabled?: boolean;
  className?: string;
}) {
  const [own, setOwn] = useState(defaultValue ?? "");
  const current = value ?? own;
  // URL から来た値は不正なことがある (from=abc・2026-02-30)。送る値はそのまま残し (API のエラーを出す)、
  // カレンダーの表示とフォーカスの基準だけを基準の日にする
  const valid = isIsoDate(current);
  const [open, setOpen] = useState(false);
  const dayRef = useRef<HTMLButtonElement>(null);

  function commit(next: string) {
    if (value === undefined) setOwn(next);
    onChange?.(next);
    setOpen(false);
  }

  return (
    <>
      {name && <input type="hidden" name={name} value={current} readOnly />}
      <Popover modal open={open} onOpenChange={setOpen}>
        <PopoverTrigger
          id={id}
          aria-describedby={`${id}-value`}
          disabled={disabled}
          className={cn(
            "flex h-9 w-full min-w-0 items-center gap-2 px-3 text-left text-sm disabled:pointer-events-none disabled:opacity-50",
            CONTROL_SURFACE,
            className,
          )}
        >
          <CalendarDays aria-hidden className="text-muted-foreground size-4 shrink-0" />
          <span id={`${id}-value`} className={cn("truncate", !current && "text-muted-foreground")}>
            {current ? (valid ? formatFullDate(current) : current) : "日付を選ぶ"}
          </span>
        </PopoverTrigger>
        <PopoverContent initialFocus={dayRef} aria-modal="true">
          <PopoverTitle className="sr-only">日付を選ぶ</PopoverTitle>
          <Calendar
            value={valid ? current : null}
            referenceDate={referenceDate}
            focusRef={dayRef}
            onSelect={commit}
            onClear={clearable ? () => commit("") : undefined}
          />
        </PopoverContent>
      </Popover>
    </>
  );
}
