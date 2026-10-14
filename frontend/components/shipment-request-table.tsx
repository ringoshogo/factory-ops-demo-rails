"use client";

import type { ReactNode } from "react";
import { TextLink } from "@/components/app-link";
import { ColumnHeads, sortCell, type Column } from "@/components/columns";
import { DateText, DueDate } from "@/components/date-text";
import { useFulfillmentDialog, type FulfillmentKind, type FulfillmentTarget } from "@/components/fulfillment-dialog";
import { RowActions, type RowAction } from "@/components/row-actions";
import { StatusBadge } from "@/components/status-badge";
import { Table, TableBody, TableCell, TableHeader, TableRow } from "@/components/ui/table";
import type { ShipmentRequestOrderField, ShipmentRequestStatus } from "@/lib/graphql/generated";
import type { Sort } from "@/lib/list";
import { OPEN_SHIPMENT_REQUEST_STATUSES } from "@/lib/shipment-request-list";
import { SHIPMENT_REQUEST_STATUS } from "@/lib/statuses";

export type ShipmentRequestRow = {
  id: string;
  dueDate: string | null;
  status: ShipmentRequestStatus;
  salesOrder: { id: string; orderNo: string };
  customer: { name: string };
  quantity: number;
  plannedDate: string | null;
};

// 出荷依頼の状況ごとの行の操作。出荷待ちは出荷指示、出荷指示済は出荷実績の計上と出荷指示の取消。
// 出荷停止中・出荷済・取消済は操作を置かない
const ACTIONS: Partial<Record<ShipmentRequestStatus, { kind: FulfillmentKind; label: string; variant?: RowAction["variant"] }[]>> = {
  READY: [{ kind: "instruct", label: "出荷指示" }],
  INSTRUCTED: [
    { kind: "ship", label: "出荷実績計上" },
    { kind: "cancelInstruction", label: "指示を取消", variant: "outline" },
  ],
};

/**
 * 出荷依頼の表と、行の操作のダイアログ。ダイアログは表が 1 つだけ持つ。操作の後の読み直しで行がタブの外へ移っても、
 * 結果の表示が消えない。
 */
export function ShipmentRequestTable({
  columns,
  sort,
  rows,
  businessDate,
}: {
  columns: Column<ShipmentRequestOrderField>[];
  sort: Sort<ShipmentRequestOrderField>;
  rows: ShipmentRequestRow[];
  businessDate: string;
}) {
  const { open, dialog } = useFulfillmentDialog({ businessDate });
  const target = (row: ShipmentRequestRow): FulfillmentTarget => ({
    salesOrderId: row.salesOrder.id,
    shipmentRequestId: row.id,
    orderNo: row.salesOrder.orderNo,
    customerName: row.customer.name,
    dueDate: row.dueDate,
  });

  return (
    <>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <ColumnHeads columns={columns} state={sort} />
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 && (
              <TableRow data-testid="empty-row">
                <TableCell colSpan={columns.length} className="text-muted-foreground py-8 text-center">
                  該当する出荷依頼がありません
                </TableCell>
              </TableRow>
            )}
            {rows.map((row) => {
              const actions = (ACTIONS[row.status] ?? []).map(
                (a): RowAction => ({ label: a.label, variant: a.variant, onSelect: () => open(a.kind, target(row)) }),
              );
              const content: Record<string, ReactNode> = {
                ORDER_NO: (
                  <TextLink href={`/supplier/sales-orders/${row.salesOrder.id}`} className="rounded-sm font-semibold">
                    {row.salesOrder.orderNo}
                  </TextLink>
                ),
                CUSTOMER_NAME: row.customer.name,
                DUE_DATE: (
                  <DueDate due={row.dueDate} open={OPEN_SHIPMENT_REQUEST_STATUSES.includes(row.status)} businessDate={businessDate} />
                ),
                PLANNED_DATE: <DateText iso={row.plannedDate} businessDate={businessDate} />,
                quantity: row.quantity,
                STATUS: <StatusBadge style={SHIPMENT_REQUEST_STATUS[row.status]} value={row.status} />,
                actions: actions.length > 0 ? <RowActions name={`${row.salesOrder.orderNo} の操作`} actions={actions} /> : null,
              };
              return (
                <TableRow key={row.id} data-testid="list-row">
                  {columns.map((c) => (
                    <TableCell key={c.key} numeric={c.numeric} truncate={c.truncate} {...sortCell(c, sort)}>
                      {content[c.key]}
                    </TableCell>
                  ))}
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>
      {dialog}
    </>
  );
}
