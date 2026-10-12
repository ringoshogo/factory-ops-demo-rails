"use client";

import { useActionState, useState } from "react";
import { DateText, DueDate } from "@/components/date-text";
import { ErrorNotice } from "@/components/error-notice";
import { FieldError } from "@/components/form-errors";
import { PageHeader } from "@/components/page-header";
import { StatusBadge } from "@/components/status-badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { inspectInboundShipment, requestPurchaseOrderCancellation } from "@/lib/actions/purchasing";
import { IDLE, type FormState } from "@/lib/form-state";
import { yen } from "@/lib/format";
import type { BuyerPurchaseOrderQuery } from "@/lib/graphql/generated";
import { OPEN_PURCHASE_ORDER_STATUSES } from "@/lib/purchase-order-list";
import { PURCHASE_ORDER_STATUS } from "@/lib/statuses";

type PurchaseOrder = NonNullable<BuyerPurchaseOrderQuery["buyer"]["purchaseOrder"]>;

const OUTCOME_LABEL = { APPROVED: "承認", REJECTED: "却下" } as const;

// 取消を依頼できる状況。受注側が確定する前と、確定して入荷を待つ間。検収した発注と取り消した発注には出さない
const CANCELLABLE = new Set(["SENT", "AWAITING_SUPPLIER_CONFIRMATION", "ACCEPTED", "INBOUND"]);

/**
 * 発注詳細。明細・入荷と検収・受注側の出荷 (経路 3)・取消依頼を 1 画面に置く。検収と取消依頼は admin だけに出す。
 * 失敗の文言は最後の操作の結果だけを出す。操作ごとに持つと、後の操作が成功しても前の失敗が残る。入力の誤りは、
 * 最後に送ったフォーム (入荷ごとの検収か、取消依頼) の、path の指す入力欄の下に出す。
 */
export function PurchaseOrderDetail({
  order,
  businessDate,
  admin,
}: {
  order: PurchaseOrder;
  businessDate: string;
  admin: boolean;
}) {
  const [last, setLast] = useState<{ state: FormState; form: string }>({ state: IDLE, form: "" });
  const track =
    (action: (prev: FormState, form: FormData) => Promise<FormState>) =>
    async (prev: FormState, form: FormData) => {
      const next = await action(prev, form);
      setLast({ state: next, form: String(form.get("inboundShipmentId") ?? "cancel") });
      return next;
    };
  const errorsFor = (form: string): FormState => (last.form === form ? last.state : IDLE);
  const [, inspect, inspecting] = useActionState(track(inspectInboundShipment), IDLE);
  const [, requestCancel, requesting] = useActionState(track(requestPurchaseOrderCancellation), IDLE);
  const open = OPEN_PURCHASE_ORDER_STATUSES.includes(order.status);

  return (
    <section className="space-y-6">
      <PageHeader
        title={
          <>
            発注 <span data-testid="order-no">{order.orderNo}</span>
          </>
        }
      >
        <span data-testid="order-status">
          <StatusBadge
            style={PURCHASE_ORDER_STATUS[order.status]}
            value={order.status}
            mark={order.cancellationPending ? "取消依頼中" : undefined}
          />
        </span>
      </PageHeader>

      <dl className="rounded-card grid gap-3 border p-4 text-sm sm:grid-cols-3">
        <div>
          <dt className="text-muted-foreground">取引先</dt>
          <dd>{order.supplier.name}</dd>
        </div>
        <div>
          <dt className="text-muted-foreground">発注日</dt>
          <dd>
            <DateText iso={order.orderDate} businessDate={businessDate} />
          </dd>
        </div>
        <div>
          <dt className="text-muted-foreground">希望納期</dt>
          <dd>
            <DueDate due={order.desiredDeliveryOn} open={open} businessDate={businessDate} />
          </dd>
        </div>
      </dl>

      {last.state.status === "error" && last.state.message && (
        <ErrorNotice data-testid="detail-error">{last.state.message}</ErrorNotice>
      )}

      <div className="space-y-3">
        <h2 className="text-base font-semibold">明細</h2>
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>自社品番</TableHead>
                <TableHead>品目名（受注確定で写した値）</TableHead>
                <TableHead numeric>数量</TableHead>
                <TableHead numeric>単価</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {order.lines.map((line) => (
                <TableRow key={line.id} data-testid="order-line">
                  <TableCell>{line.partNumber}</TableCell>
                  <TableCell truncate>{line.confirmedItemName ?? "受注側の確定待ち"}</TableCell>
                  <TableCell numeric>{line.quantity}</TableCell>
                  <TableCell numeric>{line.confirmedUnitPrice ? yen(line.confirmedUnitPrice) : "—"}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      </div>

      <div className="space-y-3">
        <h2 className="text-base font-semibold">入荷と検収</h2>
        {order.inboundShipments.length === 0 && (
          <p className="text-muted-foreground text-sm">入荷はまだありません。</p>
        )}
        {order.inboundShipments.map((inbound) => (
          <form
            key={inbound.id}
            action={inspect}
            data-testid="inbound-shipment"
            className="rounded-card space-y-3 border p-4"
          >
            <input type="hidden" name="purchaseOrderId" value={order.id} />
            <input type="hidden" name="inboundShipmentId" value={inbound.id} />
            <p className="text-sm">
              出荷日 <DateText iso={inbound.shippedOn} businessDate={businessDate} />
              {inbound.inspection && (
                <>
                  {" ・ 検収日 "}
                  <DateText iso={inbound.inspection.inspectedOn} businessDate={businessDate} />
                </>
              )}
            </p>
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>自社品番</TableHead>
                    <TableHead>品目名</TableHead>
                    <TableHead numeric>出荷数量</TableHead>
                    <TableHead numeric>受け入れ数量</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {inbound.lines.map((line, i) => (
                    <TableRow key={line.id}>
                      <TableCell>{line.purchaseOrderLine.partNumber}</TableCell>
                      <TableCell truncate>{line.purchaseOrderLine.confirmedItemName ?? "—"}</TableCell>
                      <TableCell numeric>{line.shippedQuantity}</TableCell>
                      <TableCell numeric>
                        {inbound.inspection || !admin ? (
                          (line.acceptedQuantity ?? "—")
                        ) : (
                          <>
                            <input type="hidden" name="inboundShipmentLineId" value={line.id} />
                            <Input
                              name="acceptedQuantity"
                              type="number"
                              min={0}
                              max={line.shippedQuantity}
                              defaultValue={line.shippedQuantity}
                              aria-label={`${line.purchaseOrderLine.partNumber} の受け入れ数量`}
                              className="ml-auto w-24 text-right"
                            />
                            <FieldError state={errorsFor(inbound.id)} name={`lines.${i}.acceptedQuantity`} />
                          </>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
            {admin && !inbound.inspection && (
              <Button type="submit" disabled={inspecting}>
                検収する
              </Button>
            )}
          </form>
        ))}
      </div>

      <div className="space-y-3" data-testid="supplier-shipments">
        <h2 className="text-base font-semibold">受注側の出荷</h2>
        {order.supplierShipments.length === 0 ? (
          <p data-testid="supplier-shipments-empty" className="text-muted-foreground text-sm">
            見られる出荷はありません。出荷がまだ無いか、取引先から出荷を見る付与が無いか、取引関係が失効しています。
          </p>
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>出荷日</TableHead>
                  <TableHead>自社品番</TableHead>
                  <TableHead numeric>数量</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {order.supplierShipments.flatMap((shipment, s) =>
                  shipment.lines.map((line, i) => (
                    <TableRow key={`${s}-${i}`} data-testid="supplier-shipment-row">
                      <TableCell>
                        <DateText iso={shipment.shippedOn} businessDate={businessDate} />
                      </TableCell>
                      <TableCell>{line.purchaseOrderLine.partNumber}</TableCell>
                      <TableCell numeric>{line.quantity}</TableCell>
                    </TableRow>
                  )),
                )}
              </TableBody>
            </Table>
          </div>
        )}
      </div>

      <div className="space-y-3">
        <h2 className="text-base font-semibold">取消依頼</h2>
        {order.cancellationRequests.length === 0 ? (
          <p className="text-muted-foreground text-sm">取消依頼はありません。</p>
        ) : (
          <ul className="space-y-2 text-sm">
            {order.cancellationRequests.map((request) => (
              <li key={request.id} data-testid="cancellation-request" className="rounded-card border px-3 py-2">
                <span className="font-medium">{request.outcome ? OUTCOME_LABEL[request.outcome] : "回答待ち"}</span>
                {request.decidedAt && (
                  <span className="text-muted-foreground">
                    {" "}
                    (<DateText iso={request.decidedAt} businessDate={businessDate} withTime />)
                  </span>
                )}
                <span className="text-muted-foreground"> ・ 理由：{request.reason}</span>
              </li>
            ))}
          </ul>
        )}
        {admin && CANCELLABLE.has(order.status) && !order.cancellationPending && (
          <form action={requestCancel} className="rounded-card flex flex-wrap items-end gap-2 border p-4">
            <input type="hidden" name="purchaseOrderId" value={order.id} />
            <div className="min-w-64 flex-1 space-y-1.5">
              <Label htmlFor="reason">取消の理由</Label>
              <Input id="reason" name="reason" required />
              <FieldError state={errorsFor("cancel")} name="reason" />
            </div>
            <Button type="submit" variant="outline" disabled={requesting}>
              取消を依頼する
            </Button>
          </form>
        )}
      </div>
    </section>
  );
}
