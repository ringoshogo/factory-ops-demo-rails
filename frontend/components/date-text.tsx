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
    <span className={cn("tabular-nums", note ? NOTED : PLAIN)}>
      {prefix && `${prefix} `}
      <time dateTime={due} data-testid="due-date">
        {formatDate(due, businessDate)}
      </time>
      {note && (
        <>
          {" "}
          <span data-testid={note.overdue ? "due-overdue" : "due-note"}>{note.label}</span>
        </>
      )}
    </span>
  );
}
