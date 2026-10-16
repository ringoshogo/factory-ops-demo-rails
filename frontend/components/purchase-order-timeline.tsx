import { DateText } from "@/components/date-text";
import { isCancellationEvent, PURCHASE_ORDER_TIMELINE_LABEL } from "@/lib/format";
import type { BuyerPurchaseOrderQuery } from "@/lib/graphql/generated";
import { cn } from "@/lib/utils";

type Entry = NonNullable<BuyerPurchaseOrderQuery["buyer"]["purchaseOrder"]>["timeline"][number];

/**
 * 発注の進み。API が古い順に並べた出来事を、そのまま上から出す。画面で並べ直さない。並べ方 (同じ日の日付だけの出来事を
 * 時刻の出来事の後ろに置く) は API が決め、画面で並べ直すと API の順と食い違う (docs/architecture/graphql-schema.md「発注側の視点」)。
 * 時刻を持つ出来事は日付と時刻を、日付だけの出来事 (出荷・検収・請求書の受領) は日付だけを出す。
 */
export function PurchaseOrderTimeline({ entries, businessDate }: { entries: Entry[]; businessDate: string }) {
  return (
    <div className="space-y-3">
      <h2 className="text-base font-semibold">進み</h2>
      <ol data-testid="timeline" className="rounded-card space-y-2 border p-4 text-sm">
        {entries.map((entry, i) => (
          <li key={i} data-testid="timeline-entry" data-kind={entry.kind} className="flex flex-wrap items-baseline gap-x-3">
            <span className={cn("font-medium", isCancellationEvent(entry.kind) && "text-muted-foreground")}>
              {PURCHASE_ORDER_TIMELINE_LABEL[entry.kind]}
            </span>
            {entry.occurredAt ? (
              <DateText iso={entry.occurredAt} businessDate={businessDate} withTime />
            ) : (
              <DateText iso={entry.occurredOn} businessDate={businessDate} />
            )}
          </li>
        ))}
      </ol>
    </div>
  );
}
