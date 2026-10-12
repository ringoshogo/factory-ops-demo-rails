"use server";

import { redirect } from "next/navigation";
import type { FormState } from "@/lib/form-state";
import {
  InspectInboundShipmentDocument,
  PlacePurchaseOrderDocument,
  RequestPurchaseOrderCancellationDocument,
} from "@/lib/graphql/generated";
import { mutate } from "@/lib/graphql/request";
import { settle } from "@/lib/graphql/user-errors";

const text = (form: FormData, key: string) => String(form.get(key) ?? "").trim();

/** 数の入力欄の値。空は null にし、整数でない値は API の検証に任せるため NaN のまま渡さず null にする。 */
function integer(value: string): number | null {
  return /^-?\d+$/.test(value) ? Number(value) : null;
}

/**
 * 発注を登録する。明細は自社品番と数量の組で、両方が空の行は送らない。空の行を送ると、どの行が原因か分からない
 * 入力の誤りになるからである。送った明細の番号と入力欄の行の番号がずれるので、入力の誤りの `lines.N` は
 * 入力欄の行の番号に戻してから返す。成功したら発注詳細へ移る。
 */
export async function placePurchaseOrder(_prev: FormState, form: FormData): Promise<FormState> {
  const partNumbers = form.getAll("partNumber").map(String);
  const quantities = form.getAll("quantity").map(String);
  const rows = partNumbers
    .map((partNumber, row) => ({ row, partNumber: partNumber.trim(), quantity: (quantities[row] ?? "").trim() }))
    .filter((line) => line.partNumber !== "" || line.quantity !== "");

  const quantity = rows.map((line) => integer(line.quantity));
  if (quantity.some((q) => q === null)) {
    const fieldErrors = Object.fromEntries(
      rows.flatMap((line, i) => (quantity[i] === null ? [[`lines.${line.row}.quantity`, "数量は整数で入力してください"]] : [])),
    );
    return { status: "error", fieldErrors };
  }

  const desired = text(form, "desiredDeliveryOn");
  const result = await mutate(PlacePurchaseOrderDocument, {
    input: {
      supplierTenantId: text(form, "supplierTenantId"),
      desiredDeliveryOn: desired === "" ? null : desired,
      lines: rows.map((line, i) => ({ partNumber: line.partNumber, quantity: quantity[i]! })),
    },
  });
  const state = settle(result, (data) => data.placePurchaseOrder, ["/buyer/purchase-orders"]);
  if (state.status === "ok" && result.kind === "ok") {
    redirect(`/buyer/purchase-orders/${result.data.placePurchaseOrder.purchaseOrder!.id}`);
  }
  return { ...state, fieldErrors: toRowKeys(state.fieldErrors, rows.map((line) => line.row)) };
}

/** `lines.<送った番号>.…` の鍵を `lines.<入力欄の行の番号>.…` に戻す。 */
function toRowKeys(fieldErrors: Record<string, string> | undefined, rows: number[]) {
  if (!fieldErrors) return undefined;
  return Object.fromEntries(
    Object.entries(fieldErrors).map(([key, message]) => [
      key.replace(/^lines\.(\d+)/, (_, sent: string) => `lines.${rows[Number(sent)] ?? sent}`),
      message,
    ]),
  );
}

/** 入荷を検収する。明細ごとの受け入れ数量を送る。0 は全量の不合格で、出荷数量を超えれば API が入力の誤りにする。 */
export async function inspectInboundShipment(_prev: FormState, form: FormData): Promise<FormState> {
  const purchaseOrderId = text(form, "purchaseOrderId");
  const lineIds = form.getAll("inboundShipmentLineId").map(String);
  const accepted = form.getAll("acceptedQuantity").map((v) => integer(String(v).trim()));
  if (accepted.some((q) => q === null)) {
    return { status: "error", message: "受け入れ数量は 0 以上の整数で入力してください" };
  }
  const result = await mutate(InspectInboundShipmentDocument, {
    input: {
      inboundShipmentId: text(form, "inboundShipmentId"),
      lines: lineIds.map((inboundShipmentLineId, i) => ({ inboundShipmentLineId, acceptedQuantity: accepted[i]! })),
    },
  });
  return settle(result, (data) => data.inspectInboundShipment, [
    `/buyer/purchase-orders/${purchaseOrderId}`,
    "/buyer/purchase-orders",
  ]);
}

/** 発注の取消を受注側に依頼する。受注側の審査の結果は、取消依頼の履歴に届く。 */
export async function requestPurchaseOrderCancellation(_prev: FormState, form: FormData): Promise<FormState> {
  const purchaseOrderId = text(form, "purchaseOrderId");
  const result = await mutate(RequestPurchaseOrderCancellationDocument, {
    input: { purchaseOrderId, reason: text(form, "reason") },
  });
  return settle(result, (data) => data.requestPurchaseOrderCancellation, [
    `/buyer/purchase-orders/${purchaseOrderId}`,
    "/buyer/purchase-orders",
  ]);
}
