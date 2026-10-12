"use server";

import { redirect } from "next/navigation";
import { INTEGER_MESSAGE, parseInt32 } from "@/lib/form-input";
import type { FormState } from "@/lib/form-state";
import {
  InspectInboundShipmentDocument,
  PlacePurchaseOrderDocument,
  RequestPurchaseOrderCancellationDocument,
} from "@/lib/graphql/generated";
import { mutate } from "@/lib/graphql/request";
import { settle } from "@/lib/graphql/user-errors";

const text = (form: FormData, key: string) => String(form.get(key) ?? "").trim();

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

  const quantity = rows.map((line) => parseInt32(line.quantity));
  if (quantity.some((q) => q === null)) {
    const fieldErrors = Object.fromEntries(
      rows.flatMap((line, i) => (quantity[i] === null ? [[`lines.${line.row}.quantity`, INTEGER_MESSAGE]] : [])),
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

/**
 * 入荷を検収する。明細ごとの受け入れ数量を、入荷の明細の並びのまま送る。0 は全量の不合格で、出荷数量を超えれば API が
 * 入力の誤り (`lines.<番号>.acceptedQuantity`) にし、画面はその番号の明細の入力欄の下に出す。
 */
export async function inspectInboundShipment(_prev: FormState, form: FormData): Promise<FormState> {
  const purchaseOrderId = text(form, "purchaseOrderId");
  const lineIds = form.getAll("inboundShipmentLineId").map(String);
  const accepted = form.getAll("acceptedQuantity").map((v) => parseInt32(String(v)));
  if (accepted.some((q) => q === null)) {
    const fieldErrors = Object.fromEntries(
      accepted.flatMap((q, i) => (q === null ? [[`lines.${i}.acceptedQuantity`, INTEGER_MESSAGE]] : [])),
    );
    return { status: "error", fieldErrors };
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
