"use client";

import { TextLink } from "@/components/app-link";
import { DueDate } from "@/components/date-text";
import { useFulfillmentDialog, type FulfillmentKind, type FulfillmentTarget } from "@/components/fulfillment-dialog";
import { StatusBadge, TONE_LINE } from "@/components/status-badge";
import { BUTTON_SM_HEIGHT, Button } from "@/components/ui/button";
import type { SalesOrderStatus, ShipmentRequestStatus } from "@/lib/graphql/generated";
import { nextAction, orderMark, type CardAction } from "@/lib/sales-order-flow";
import { OPEN_SALES_ORDER_STATUSES } from "@/lib/sales-order-list";
import { SALES_ORDER_STATUS } from "@/lib/statuses";
import { cn } from "@/lib/utils";

export type BoardCard = {
  id: string;
  orderNo: string;
  dueDate: string | null;
  status: SalesOrderStatus;
  cancellationReviewPending: boolean;
  customerName: string;
  /** 受注の合計の表示 (totalAmountText)。品番照合待ちの明細を含む受注は、金額の代わりに「照合待ち」。 */
  total: string;
  shipmentRequest: { id: string; status: ShipmentRequestStatus } | null;
};

/** `total` は API の totalCount (遷移先の受注一覧と同じ状況の絞り込みで数える)。カードは最大 10 件で、カードの数から数えない。 */
export type BoardColumn = { status: SalesOrderStatus; total: number; cards: BoardCard[] };

const ACTION_LABELS: Record<CardAction, string> = { allocate: "引当", instruct: "出荷指示", ship: "出荷実績計上" };

const target = (card: BoardCard): FulfillmentTarget => ({
  salesOrderId: card.id,
  shipmentRequestId: card.shipmentRequest?.id ?? null,
  orderNo: card.orderNo,
  customerName: card.customerName,
  dueDate: card.dueDate,
});

const headingIdOf = (status: SalesOrderStatus) => `kanban-${status}`;

/**
 * 受注のかんばん。列は `<section>`、カードは `<ul>`/`<li>` で組み、表の行を使わない (表の行を数える確かめに
 * ダッシュボードのカードを混ぜない)。ダイアログはボードが 1 つだけ持つ。
 */
export function KanbanBoard({ columns, businessDate }: { columns: BoardColumn[]; businessDate: string }) {
  const { open, dialog } = useFulfillmentDialog({
    businessDate,
    // 開いたボタンのカードは読み直しで作り直されている。移った先のカードの受注番号へ戻し、見つからなければ
    // (10 件の外へ移った) 操作を始めた列の見出しへ戻す
    finalFocus: (t) =>
      document.querySelector<HTMLElement>(`[data-testid="kanban-card"][data-order-id="${CSS.escape(t.salesOrderId)}"] a`) ??
      document.getElementById(headingIdOf(columns.find((c) => c.cards.some((card) => card.id === t.salesOrderId))?.status ?? "RECEIVED")),
  });

  return (
    <>
      {/* 列は最小 232px で、広い画面では幅を分け合う。7 列が収まらない幅では、この容器だけが横にスクロールする。
          左右の 4px はカードの縁 (影のリング) をスクロール領域で切らないため */}
      <div
        data-testid="kanban-board"
        className="-mx-1 grid auto-cols-[minmax(232px,1fr)] grid-flow-col gap-4 overflow-x-auto px-1 pb-1.5"
      >
        {columns.map((column) => (
          <Column key={column.status} column={column} businessDate={businessDate} onAction={(kind, card) => open(kind, target(card))} />
        ))}
      </div>
      {dialog}
    </>
  );
}

function Column({
  column,
  businessDate,
  onAction,
}: {
  column: BoardColumn;
  businessDate: string;
  onAction: (kind: FulfillmentKind, card: BoardCard) => void;
}) {
  const headingId = headingIdOf(column.status);
  const style = SALES_ORDER_STATUS[column.status];
  return (
    <section
      data-testid="kanban-column"
      data-status={column.status}
      aria-labelledby={headingId}
      // relative: 中の sr-only (絶対配置) の基準をボードの中に置く。無いと基準がビューポートになり、
      // スクロール領域で切られずにページ全体を横に広げる。列は塗らず、見出しの下に状況の色の 2px の線を引く
      className="relative flex min-w-0 flex-col gap-2.5"
    >
      <header className={`flex items-center justify-between gap-2 border-b-2 px-0.5 pb-2 ${TONE_LINE[style.tone]}`}>
        <h3 id={headingId} tabIndex={-1} className="flex items-center gap-2 text-[13px] font-normal outline-none">
          <StatusBadge style={style} />
          <span className="text-muted-foreground tabular-nums">
            <span data-testid="kanban-count">{column.total}</span>
            <span className="sr-only"> 件</span>
          </span>
        </h3>
        <TextLink href={`/supplier/sales-orders?status=${column.status}`} className="text-xs font-medium">
          すべて見る
        </TextLink>
      </header>

      {column.cards.length === 0 ? (
        <p className="text-muted-foreground py-6 text-center text-xs">該当なし</p>
      ) : (
        // 列の中を縦にスクロールする。内側の余白はカードの影 (縁のリング) をスクロール領域で切らないため
        <ul data-testid="kanban-cards" className="-m-1 flex max-h-[60vh] flex-col gap-2.5 overflow-y-auto p-1">
          {column.cards.map((card) => (
            <Card key={card.id} card={card} businessDate={businessDate} onAction={onAction} />
          ))}
        </ul>
      )}
    </section>
  );
}

function Card({
  card,
  businessDate,
  onAction,
}: {
  card: BoardCard;
  businessDate: string;
  onAction: (kind: FulfillmentKind, card: BoardCard) => void;
}) {
  const kind = nextAction(card);
  const mark = orderMark(card);

  return (
    <li
      data-testid="kanban-card"
      data-order-id={card.id}
      // 浮いた面と影。縁は影のリングで描き、枠線を持たない
      className="bg-surface-raised rounded-card shadow-card hover:shadow-card-hover flex flex-col gap-1.5 p-3.5 transition-shadow duration-150"
    >
      <div className="flex items-baseline justify-between gap-2 text-[13px]">
        {/* カード全体をリンクにしない。操作のボタンと別のフォーカスの対象にする */}
        <TextLink href={`/supplier/sales-orders/${card.id}`} className="font-semibold">
          {card.orderNo}
        </TextLink>
        <span className="text-[15px] font-semibold tabular-nums">{card.total}</span>
      </div>
      <p className="truncate font-medium" title={card.customerName}>
        {card.customerName}
      </p>
      <p className="mt-1.5 truncate text-xs">
        <DueDate due={card.dueDate} open={OPEN_SALES_ORDER_STATUSES.includes(card.status)} businessDate={businessDate} prefix="納期" />
      </p>
      {/* 最下段は印と操作のボタンの段。ボタンの無いカードも同じ高さを取り、カードの高さを中身によらずそろえる。
          納期と同じ段に置くと、カードの幅 (最小 232px) では納期の文言 (「明日」など) が収まらない */}
      <div className={cn("flex items-center justify-between gap-2", BUTTON_SM_HEIGHT)}>
        <span className="min-w-0 truncate">
          {mark && (
            <span data-testid="card-mark" className="bg-warning text-warning-foreground rounded-badge px-1.5 py-px text-xs font-medium">
              {mark}
            </span>
          )}
        </span>
        {kind && (
          <Button size="sm" variant="outline" onClick={() => onAction(kind, card)}>
            {ACTION_LABELS[kind]}
          </Button>
        )}
      </div>
    </li>
  );
}
