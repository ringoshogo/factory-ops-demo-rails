"use client";

import { useActionState, useState } from "react";
import { DateText, DueDate } from "@/components/date-text";
import { ErrorNotice } from "@/components/error-notice";
import { useFulfillmentDialog, type FulfillmentKind } from "@/components/fulfillment-dialog";
import { PageHeader } from "@/components/page-header";
import { StatusBadge } from "@/components/status-badge";
import { Button } from "@/components/ui/button";
import { approveCancellationReview, cancelSalesOrder, rejectCancellationReview } from "@/lib/actions/fulfillment";
import { IDLE, type FormState } from "@/lib/form-state";
import { totalAmountText, yen } from "@/lib/format";
import type { SupplierSalesOrderQuery } from "@/lib/graphql/generated";
import {
  canAllocate,
  canCancel,
  canCancelInstruction,
  canInstruct,
  canShip,
  orderMark,
} from "@/lib/sales-order-flow";
import { OPEN_SALES_ORDER_STATUSES } from "@/lib/sales-order-list";
import { SALES_ORDER_STATUS, SHIPMENT_REQUEST_STATUS } from "@/lib/statuses";

type Order = NonNullable<SupplierSalesOrderQuery["supplier"]["salesOrder"]>;

/** 単価の決まった明細の金額。合計は API の totalAmount を出し、明細から足さない。 */
const lineAmount = (unitPrice: string, quantity: number) => BigInt(unitPrice) * BigInt(quantity);

/**
 * 受注詳細。出せる操作は lib/sales-order-flow.ts で受注の状況と出荷依頼の状況から決め、押せるのに通らないボタンを
 * 出さない。取消と取消の審査は admin に限るので、`admin` のときだけ出す。
 */
export function SalesOrderDetail({ order, businessDate, admin }: { order: Order; businessDate: string; admin: boolean }) {
  const { open, dialog } = useFulfillmentDialog({ businessDate });
  const request = order.shipmentRequest;
  const openDialog = (kind: FulfillmentKind) =>
    open(kind, {
      salesOrderId: order.id,
      shipmentRequestId: request?.id ?? null,
      orderNo: order.orderNo,
      customerName: order.customer.name,
      dueDate: request?.dueDate ?? order.dueDate,
    });
  const pendingReview = order.cancellationReviews.find((r) => r.decision === null);

  // 失敗の表示は 1 か所に集め、最後の操作の結果だけを持つ (操作ごとに持つと、後の操作が成功しても前の失敗が残る)
  const [last, setLast] = useState<FormState>(IDLE);
  const track =
    (action: (prev: FormState, form: FormData) => Promise<FormState>) =>
    async (prev: FormState, form: FormData) => {
      const next = await action(prev, form);
      setLast(next);
      return next;
    };
  const [, cancel, cancelling] = useActionState(track(cancelSalesOrder), IDLE);
  const [, approve, approving] = useActionState(track(approveCancellationReview), IDLE);
  const [, reject, rejecting] = useActionState(track(rejectCancellationReview), IDLE);

  return (
    <section className="space-y-5">
      <PageHeader
        title={
          <>
            受注 <span data-testid="order-no">{order.orderNo}</span>
          </>
        }
      >
        <span data-testid="order-status">
          <StatusBadge style={SALES_ORDER_STATUS[order.status]} value={order.status} mark={orderMark(order)} />
        </span>
      </PageHeader>

      <dl className="rounded-card grid gap-3 border p-4 text-sm sm:grid-cols-4">
        <div className="min-w-0">
          <dt className="text-muted-foreground">取引先</dt>
          <dd className="truncate" title={order.customer.name}>
            {order.customer.name}
          </dd>
        </div>
        <div>
          <dt className="text-muted-foreground">受注日</dt>
          <dd>
            <DateText iso={order.orderDate} businessDate={businessDate} />
          </dd>
        </div>
        <div>
          <dt className="text-muted-foreground">希望納期</dt>
          <dd>
            <DueDate due={order.dueDate} open={OPEN_SALES_ORDER_STATUSES.includes(order.status)} businessDate={businessDate} />
          </dd>
        </div>
        <div>
          <dt className="text-muted-foreground">受注合計（税抜き）</dt>
          <dd data-testid="order-total" className="tabular-nums">
            {totalAmountText(order.totalAmount, "salesOrder", order.status)}
          </dd>
        </div>
      </dl>

      {last.status === "error" && <ErrorNotice data-testid="detail-error">{last.message}</ErrorNotice>}

      {pendingReview && (
        <div data-testid="cancellation-review" className="bg-warning text-warning-foreground rounded-card space-y-3 p-4 text-sm">
          <p>
            発注側から取消の依頼が届いています（
            <DateText iso={pendingReview.requestedAt} businessDate={businessDate} withTime className="text-current" />
            ）。出荷依頼は出荷停止中です。
          </p>
          {admin && (
            <div className="flex flex-wrap gap-2">
              <form action={approve}>
                <input type="hidden" name="sales_order_id" value={order.id} />
                <input type="hidden" name="cancellation_review_id" value={pendingReview.id} />
                <Button type="submit" size="sm" disabled={approving}>
                  取消を承認
                </Button>
              </form>
              <form action={reject}>
                <input type="hidden" name="sales_order_id" value={order.id} />
                <input type="hidden" name="cancellation_review_id" value={pendingReview.id} />
                <Button type="submit" size="sm" variant="outline" disabled={rejecting}>
                  取消を却下
                </Button>
              </form>
            </div>
          )}
        </div>
      )}

      <ul className="space-y-3">
        {order.lines.map((line) => (
          <li key={line.id} data-testid="order-line" className="rounded-card space-y-2 border p-4">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <span className="min-w-0 font-medium">
                {line.item ? (
                  <>
                    {line.item.code} {line.itemName ?? line.item.name}
                  </>
                ) : (
                  <span className="text-caution">品番照合待ち</span>
                )}
                <span className="text-muted-foreground ml-2 text-xs font-normal">得意先品番 {line.customerPartNumber}</span>
              </span>
              <span className="text-muted-foreground text-sm tabular-nums">
                {line.unitPrice ? (
                  <>
                    {yen(line.unitPrice)} 円 × {line.quantity} = {yen(lineAmount(line.unitPrice, line.quantity))} 円
                  </>
                ) : (
                  <>数量 {line.quantity}</>
                )}
              </span>
            </div>
            <div className="text-sm">
              引当済{" "}
              <span data-testid="allocated-qty" className="tabular-nums">
                {line.allocatedQuantity}
              </span>
              {" / 数量 "}
              <span className="tabular-nums">{line.quantity}</span>
            </div>
          </li>
        ))}
      </ul>

      {request && (
        <dl data-testid="shipment-request" className="rounded-card grid gap-3 border p-4 text-sm sm:grid-cols-3">
          <div>
            <dt className="text-muted-foreground">出荷依頼</dt>
            <dd>
              <StatusBadge style={SHIPMENT_REQUEST_STATUS[request.status]} value={request.status} />
            </dd>
          </div>
          <div>
            <dt className="text-muted-foreground">出荷期限</dt>
            <dd>
              <DateText iso={request.dueDate} businessDate={businessDate} />
            </dd>
          </div>
          <div>
            <dt className="text-muted-foreground">出荷予定日</dt>
            <dd>
              <DateText iso={request.instruction?.plannedDate ?? null} businessDate={businessDate} />
            </dd>
          </div>
        </dl>
      )}

      <div className="flex flex-wrap gap-2">
        {canAllocate(order) && <Button onClick={() => openDialog("allocate")}>引当</Button>}
        {canInstruct(order) && <Button onClick={() => openDialog("instruct")}>出荷指示を作成</Button>}
        {canShip(order) && <Button onClick={() => openDialog("ship")}>出荷実績計上</Button>}
        {canCancelInstruction(order) && (
          <Button variant="outline" onClick={() => openDialog("cancelInstruction")}>
            出荷指示を取消
          </Button>
        )}
      </div>

      {admin && canCancel(order) && !pendingReview && (
        <form action={cancel}>
          <input type="hidden" name="sales_order_id" value={order.id} />
          <Button type="submit" variant="ghost" className="text-destructive" disabled={cancelling}>
            この受注を取り消す
          </Button>
        </form>
      )}
      {dialog}
    </section>
  );
}
