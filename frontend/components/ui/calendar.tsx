"use client"

import { ChevronLeft, ChevronRight } from "lucide-react"
import { useEffect, useId, useRef, useState, type KeyboardEvent, type RefObject } from "react"
import { cn } from "cn"
import { Button, buttonVariants } from "@/components/ui/button"
import { NativeSelect } from "@/components/ui/native-select"
import { PopoverClose } from "@/components/ui/popover"
import { monthGrid, moveDate, withMonth, type CalendarKey } from "@/lib/calendar"
import { formatFullDate } from "@/lib/dates"

const WEEKDAYS = ["日", "月", "火", "水", "木", "金", "土"] as const
const MONTHS = Array.from({ length: 12 }, (_, i) => i + 1)
const YEAR_SPAN = 10

const ymOf = (iso: string) => iso.split("-").map(Number) as [number, number, number]

/** キーボードの操作を格子の移動に読み替える (Shift 付きの PageUp/PageDown は年)。 */
function calendarKey(e: KeyboardEvent): CalendarKey | null {
  switch (e.key) {
    case "ArrowLeft":
    case "ArrowRight":
    case "ArrowUp":
    case "ArrowDown":
    case "Home":
    case "End":
      return e.key
    case "PageUp":
    case "PageDown":
      return e.shiftKey ? `Shift+${e.key}` : e.key
    default:
      return null
  }
}

/**
 * 日付の格子 (WAI-ARIA APG の Date Picker Dialog)。DateField のポップオーバーの中身。
 *
 * - 上から「前の月」・年と月の選択欄・「次の月」、日付の格子、下に「日付を消す」(onClear があるとき) と「閉じる」
 * - 格子は `role="grid"` で、名前は年月の見出し (`aria-live="polite"`: 月が変わると読み上げる)
 * - 選んでいる日は gridcell に `aria-selected="true"`。Tab の対象は格子の中で 1 つ (フォーカス中の日) だけ
 * - ←→↑↓・Home/End・PageUp/PageDown (Shift で年) で動き、Enter・Space (ボタンの押下) で確定する
 *
 * 開くたびに作り直される (ポップオーバーは閉じると DOM から外す) ので、フォーカス中の日は
 * 選んでいる日 (無ければ基準の日) から始まる。`focusRef` はその日のボタンを指し、開いたときの初期フォーカスに使う。
 */
export function Calendar({
  value,
  referenceDate,
  focusRef,
  onSelect,
  onClear,
}: {
  value: string | null
  referenceDate: string
  focusRef: RefObject<HTMLButtonElement | null>
  onSelect: (iso: string) => void
  onClear?: () => void
}) {
  const id = useId()
  const [focused, setFocused] = useState(value ?? referenceDate)
  // キーで動いたときだけ、描き直した後にその日へフォーカスを移す (選択欄・月のボタンからは奪わない)
  const moved = useRef(false)
  const [year, month] = ymOf(focused)
  const weeks = monthGrid(year, month)

  useEffect(() => {
    if (!moved.current) return
    moved.current = false
    focusRef.current?.focus()
  }, [focused, focusRef])

  const years = new Set<number>()
  const base = ymOf(referenceDate)[0]
  for (let y = base - YEAR_SPAN; y <= base + YEAR_SPAN; y++) years.add(y)
  if (value) years.add(ymOf(value)[0])
  years.add(year) // Shift+PageUp/PageDown で範囲の外へ出ても、選択欄が表示中の年を指す

  function onKeyDown(e: KeyboardEvent<HTMLTableElement>) {
    const key = calendarKey(e)
    if (!key) return
    e.preventDefault()
    moved.current = true
    setFocused((d) => moveDate(d, key))
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-1">
        <Button type="button" variant="ghost" size="icon-sm" aria-label="前の月" onClick={() => setFocused((d) => moveDate(d, "PageUp"))}>
          <ChevronLeft aria-hidden />
        </Button>
        <NativeSelect
          aria-label="年"
          value={year}
          onChange={(e) => setFocused((d) => withMonth(d, Number(e.target.value), month))}
        >
          {[...years].sort((a, b) => a - b).map((y) => (
            <option key={y} value={y}>
              {y}年
            </option>
          ))}
        </NativeSelect>
        <NativeSelect
          aria-label="月"
          value={month}
          onChange={(e) => setFocused((d) => withMonth(d, year, Number(e.target.value)))}
        >
          {MONTHS.map((m) => (
            <option key={m} value={m}>
              {m}月
            </option>
          ))}
        </NativeSelect>
        <Button type="button" variant="ghost" size="icon-sm" aria-label="次の月" onClick={() => setFocused((d) => moveDate(d, "PageDown"))}>
          <ChevronRight aria-hidden />
        </Button>
      </div>
      <p id={`${id}-month`} aria-live="polite" className="sr-only">
        {year}年{month}月
      </p>
      <table role="grid" aria-labelledby={`${id}-month`} className="w-full border-collapse text-center text-sm" onKeyDown={onKeyDown}>
        <thead>
          <tr>
            {WEEKDAYS.map((w) => (
              <th key={w} scope="col" abbr={`${w}曜日`} className="text-muted-foreground size-9 text-xs font-normal">
                {w}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {weeks.map((week, i) => (
            <tr key={i}>
              {week.map((day, j) => (
                <td key={j} role="gridcell" aria-selected={day !== null && day === value ? true : undefined} className="p-0">
                  {day && (
                    <button
                      type="button"
                      ref={day === focused ? focusRef : undefined}
                      tabIndex={day === focused ? 0 : -1}
                      aria-label={formatFullDate(day)}
                      onClick={() => onSelect(day)}
                      // 選んでいる日は主ボタンの面 (--primary・白文字)、他はゴーストのボタン
                      className={cn(
                        buttonVariants({ variant: day === value ? "default" : "ghost", size: "icon-lg" }),
                        "font-normal tabular-nums"
                      )}
                    >
                      {ymOf(day)[2]}
                    </button>
                  )}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      <div className="flex justify-end gap-2">
        {onClear && (
          <Button type="button" variant="outline" size="sm" onClick={onClear}>
            日付を消す
          </Button>
        )}
        <PopoverClose render={<Button type="button" variant="outline" size="sm" />}>閉じる</PopoverClose>
      </div>
    </div>
  )
}
