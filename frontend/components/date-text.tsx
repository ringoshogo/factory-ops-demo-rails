import { dueNote, formatDate, formatDateTime } from "@/lib/dates";
import { cn } from "@/lib/utils";

/**
 * 日付の描き方。値は `<time dateTime>` に持たせ、表示は `lib/dates.ts` で作る。文言を添えない日付は文字 3、
 * 添えた日付は注意色・500。フックを持たないので、サーバー部品とクライアント部品 (かんばん) の両方が使える。
 */

const PLAIN = "text-muted-foreground";
const NOTED = "text-caution font-medium";

/** 文言を添えない日付 ("10月8日")。日時は `withTime` で "10月8日 14:32"。値が無ければ「—」。 */
export function DateText({
  iso,
  businessDate,
  withTime = false,
  className,
}: {
  iso: string | null;
  businessDate: string | null;
  withTime?: boolean;
  className?: string;
}) {
  if (!iso) return <span className={PLAIN}>—</span>;
  return (
    <time dateTime={iso} className={cn(PLAIN, "tabular-nums", className)}>
      {withTime ? formatDateTime(iso, businessDate) : formatDate(iso, businessDate)}
    </time>
  );
}

/**
 * 期限 (希望納期・出荷期限)。未完了の伝票で 3 日以内か超過なら文言を後ろに添え、日付ごと注意色にする。
 * かんばんのカードは `prefix` で「納期」を前に置く。期限が無ければ「—」。
 *
 * 表のセルは折り返さない (whitespace-nowrap) ので、文言を添えると列の最小幅が「日付 文言」の幅になり、列の多い表が
 * パネルからはみ出す。表のセルの中でだけ、日付と文言の間の空白で折り返せるようにし、日付と文言の中では折り返さない
 * (日本語は文字の間で折り返せるので、全体を折り返し可にすると「10月1」と「6日」に割れる)。表の外 (かんばんのカード) は
 * 1 行のまま省略し、カードの高さをそろえる。
 */
export function DueDate({
  due,
  open,
  businessDate,
  prefix,
}: {
  due: string | null;
  open: boolean;
  businessDate: string | null;
  prefix?: string;
}) {
  if (!due) return <span className={PLAIN}>—</span>;
  const note = dueNote(due, open, businessDate);
  return (
    <span className={cn("tabular-nums in-data-[slot=table-cell]:whitespace-normal", note ? NOTED : PLAIN)}>
      <span className="whitespace-nowrap">
        {prefix && `${prefix} `}
        <time dateTime={due} data-testid="due-date">
          {formatDate(due, businessDate)}
        </time>
      </span>
      {note && (
        <>
          {" "}
          <span data-testid={note.overdue ? "due-overdue" : "due-note"} className="whitespace-nowrap">
            {note.label}
          </span>
        </>
      )}
    </span>
  );
}
