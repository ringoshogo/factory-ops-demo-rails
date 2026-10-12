/**
 * 日付の入力のカレンダーの計算 (仕様 cycle-03 §5)。日付は YYYY-MM-DD の文字列のまま
 * UTC の日として計算し、ブラウザのタイムゾーンに依らない。
 */

/** 格子の上で日付を動かすキー (WAI-ARIA APG の Date Picker Dialog)。 */
export type CalendarKey =
  | "ArrowLeft"
  | "ArrowRight"
  | "ArrowUp"
  | "ArrowDown"
  | "Home"
  | "End"
  | "PageUp"
  | "PageDown"
  | "Shift+PageUp"
  | "Shift+PageDown";

const pad = (n: number, width = 2) => String(n).padStart(width, "0");

function toIso(date: Date): string {
  return `${pad(date.getUTCFullYear(), 4)}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
}

/**
 * UTC の日付を作る。month は 0 始まりで、範囲外の日・月は繰り上げる。
 * Date.UTC は 0〜99 年を 1900 年代に読み替えるので、setUTCFullYear で年を保つ。
 */
export function utcDate(year: number, monthIndex: number, day: number): Date {
  const date = new Date(0);
  date.setUTCFullYear(year, monthIndex, day);
  return date;
}

function parse(iso: string): Date {
  const [year, month, day] = iso.split("-").map(Number);
  return utcDate(year, month - 1, day);
}

const daysInMonth = (year: number, month: number) => utcDate(year, month, 0).getUTCDate();

/** 6 週 × 7 日の格子 (日曜始まり)。month は 1〜12。月の外は null。 */
export function monthGrid(year: number, month: number): (string | null)[][] {
  const offset = utcDate(year, month - 1, 1).getUTCDay();
  const last = daysInMonth(year, month);
  return Array.from({ length: 6 }, (_, week) =>
    Array.from({ length: 7 }, (_, weekday) => {
      const day = week * 7 + weekday - offset + 1;
      return day >= 1 && day <= last ? `${pad(year, 4)}-${pad(month)}-${pad(day)}` : null;
    }),
  );
}

function addDays(iso: string, days: number): string {
  const date = parse(iso);
  date.setUTCDate(date.getUTCDate() + days);
  return toIso(date);
}

/** 月を動かし、移動先の月に無い日 (31日など) はその月の末日に丸める。 */
function addMonths(iso: string, months: number): string {
  const [year, month, day] = iso.split("-").map(Number);
  const index = year * 12 + (month - 1) + months;
  const y = Math.floor(index / 12);
  const m = (index % 12) + 1;
  return `${pad(y, 4)}-${pad(m)}-${pad(Math.min(day, daysInMonth(y, m)))}`;
}

/** 年・月の選択欄で表示する月を替える。日は保ち、その月に無い日は月末に丸める。month は 1〜12。 */
export function withMonth(iso: string, year: number, month: number): string {
  const [y, m] = iso.split("-").map(Number);
  return addMonths(iso, year * 12 + month - (y * 12 + m));
}

/** キーごとの移動。←→ 1 日・↑↓ 1 週・Home/End 週の日曜/土曜・PageUp/Down 月・Shift 付きは年。 */
export function moveDate(iso: string, key: CalendarKey): string {
  switch (key) {
    case "ArrowLeft":
      return addDays(iso, -1);
    case "ArrowRight":
      return addDays(iso, 1);
    case "ArrowUp":
      return addDays(iso, -7);
    case "ArrowDown":
      return addDays(iso, 7);
    case "Home":
      return addDays(iso, -parse(iso).getUTCDay());
    case "End":
      return addDays(iso, 6 - parse(iso).getUTCDay());
    case "PageUp":
      return addMonths(iso, -1);
    case "PageDown":
      return addMonths(iso, 1);
    case "Shift+PageUp":
      return addMonths(iso, -12);
    case "Shift+PageDown":
      return addMonths(iso, 12);
  }
}

/** 実在する日付の YYYY-MM-DD か (2月30日などを拒む)。 */
export function isIsoDate(raw: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return false;
  const [year, month, day] = raw.split("-").map(Number);
  return month >= 1 && month <= 12 && day >= 1 && day <= daysInMonth(year, month);
}
