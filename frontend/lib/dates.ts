import { isIsoDate, utcDate } from "./calendar";

/**
 * 日付の表示と納期の判定。next/headers を読み込まないので、サーバー部品とクライアント部品の両方が import できる。
 * 日付 (YYYY-MM-DD) は文字列のまま UTC の日として扱い、ブラウザのタイムゾーンに依らない。業務の今日は API が返す
 * `supplier.dashboard.businessDate` を受け取り、ブラウザやサーバーの時計で決めない。業務の今日を決める場所が
 * Rails と Next の 2 か所になると、日本時間の 0〜9 時に画面の今日が API とずれる。
 */

const WEEKDAYS = ["日", "月", "火", "水", "木", "金", "土"] as const;

type Ymd = { year: number; month: number; day: number };

function parseYmd(iso: string): Ymd {
  const [year, month, day] = iso.slice(0, 10).split("-").map(Number);
  return { year, month, day };
}

const yearOf = (iso: string) => parseYmd(iso).year;

function monthDay({ year, month, day }: Ymd, withYear: boolean): string {
  return withYear ? `${year}年${month}月${day}日` : `${month}月${day}日`;
}

/** "10月8日"。年が業務日付と違えば "2025年12月26日"。業務日付が分からなければ年を付ける。 */
export function formatDate(iso: string, businessDate: string | null): string {
  const ymd = parseYmd(iso);
  return monthDay(ymd, businessDate === null || ymd.year !== yearOf(businessDate));
}

const TOKYO = new Intl.DateTimeFormat("en-US", {
  timeZone: "Asia/Tokyo",
  year: "numeric",
  month: "numeric",
  day: "numeric",
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
});

/** 在庫移動履歴の日時。"10月8日 14:32"(Asia/Tokyo)。年の規則は formatDate と同じ。 */
export function formatDateTime(iso: string, businessDate: string | null): string {
  const parts = Object.fromEntries(TOKYO.formatToParts(new Date(iso)).map((p) => [p.type, p.value]));
  const ymd = { year: Number(parts.year), month: Number(parts.month), day: Number(parts.day) };
  const withYear = businessDate === null || ymd.year !== yearOf(businessDate);
  return `${monthDay(ymd, withYear)} ${parts.hour}:${parts.minute}`;
}

/** ダッシュボードの業務の今日。"2026年10月7日(水)"。 */
export function formatBusinessDate(iso: string): string {
  const ymd = parseYmd(iso);
  const weekday = WEEKDAYS[utcDate(ymd.year, ymd.month - 1, ymd.day).getUTCDay()];
  return `${monthDay(ymd, true)}(${weekday})`;
}

/**
 * 日付の期間のボタンの値。両方なら "10月1日〜10月8日"、片側なら
 * "10月1日以降" / "10月8日以前"、無ければ "期間を選ぶ"。年の付け方は formatDate と同じ。
 */
export function dateRangeLabel(from: string, to: string, businessDate: string | null): string {
  // URL から来た不正な値 (abc・2026-02-30) は日付として整形せず、そのまま出す (API はエラーを返し list-error に出る)
  const show = (iso: string) => (isIsoDate(iso) ? formatDate(iso, businessDate) : iso);
  if (from && to) return `${show(from)}〜${show(to)}`;
  if (from) return `${show(from)}以降`;
  if (to) return `${show(to)}以前`;
  return "期間を選ぶ";
}

const TOKYO_DATE = new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Tokyo" });

/** Asia/Tokyo の今日 (YYYY-MM-DD)。業務の今日が得られないときの、カレンダーの基準の日。 */
export function todayInTokyo(): string {
  return TOKYO_DATE.format(new Date());
}

/** 日付ボタンの表示。"2026年10月8日"。 */
export function formatFullDate(iso: string): string {
  return monthDay(parseYmd(iso), true);
}

const DAY_MS = 24 * 60 * 60 * 1000;
const utcDay = (iso: string) => {
  const { year, month, day } = parseYmd(iso);
  return utcDate(year, month - 1, day).getTime();
};

/** from から to までの日数 (to が後なら正)。どちらも YYYY-MM-DD を UTC の日として計算する。 */
export function daysUntil(from: string, to: string): number {
  return Math.round((utcDay(to) - utcDay(from)) / DAY_MS);
}

/** 未完了で、期限が業務の今日より前 (どちらも YYYY-MM-DD)。期限の超過を決める唯一の関数。 */
export function isOverdue(due: string, open: boolean, businessDate: string): boolean {
  return open && due < businessDate;
}

export type DueNote = { label: string; overdue: boolean };

/**
 * 未完了の伝票の期限 (希望納期・出荷期限) に添える文言。過ぎたもの "期限超過"、0 日 "今日"、1 日 "明日"、
 * 2〜3 日 "あと N日"。4 日以上先・完了・業務の今日が分からないときは null。
 */
export function dueNote(due: string, open: boolean, businessDate: string | null): DueNote | null {
  if (businessDate === null || !open) return null;
  if (isOverdue(due, open, businessDate)) return { label: "期限超過", overdue: true };
  const days = daysUntil(businessDate, due);
  if (days === 0) return { label: "今日", overdue: false };
  if (days === 1) return { label: "明日", overdue: false };
  if (days <= 3) return { label: `あと${days}日`, overdue: false };
  return null;
}
