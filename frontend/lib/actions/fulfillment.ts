"use server";

import type { FormState } from "@/lib/form-state";
import {
  AllocateSalesOrderDocument,
  ApproveCancellationReviewDocument,
  CancelSalesOrderDocument,
  CancelShippingInstructionDocument,
  CreateShippingInstructionDocument,
  PostShipmentDocument,
  RejectCancellationReviewDocument,
} from "@/lib/graphql/generated";
import { mutate } from "@/lib/graphql/request";
import { settle } from "@/lib/graphql/user-errors";

// 受注と出荷依頼の操作。どの操作も、受注の状況・かんばん・出荷依頼の状況を同時に変えるので、それらを映す画面を
// まとめて読み直す。受注詳細は、フォームが送る受注の ID で道を作る

function str(form: FormData, key: string): string {
  return String(form.get(key) ?? "").trim();
}

function pathsFor(form: FormData): string[] {
  const orderId = str(form, "sales_order_id");
  return [
    "/supplier/dashboard",
    "/supplier/sales-orders",
    "/supplier/shipment-requests",
    ...(orderId ? [`/supplier/sales-orders/${orderId}`] : []),
  ];
}

/** 受注の単位で、有効在庫の範囲で引き当てる。足りなければ一部引当になる。 */
export async function allocateSalesOrder(_prev: FormState, form: FormData): Promise<FormState> {
  const result = await mutate(AllocateSalesOrderDocument, { input: { salesOrderId: str(form, "sales_order_id") } });
  return settle(result, (d) => d.allocateSalesOrder, pathsFor(form));
}

export async function createShippingInstruction(_prev: FormState, form: FormData): Promise<FormState> {
  const result = await mutate(CreateShippingInstructionDocument, {
    input: { shipmentRequestId: str(form, "shipment_request_id"), plannedDate: str(form, "planned_date") },
  });
  return settle(result, (d) => d.createShippingInstruction, pathsFor(form));
}

export async function cancelShippingInstruction(_prev: FormState, form: FormData): Promise<FormState> {
  const result = await mutate(CancelShippingInstructionDocument, {
    input: { shipmentRequestId: str(form, "shipment_request_id") },
  });
  return settle(result, (d) => d.cancelShippingInstruction, pathsFor(form));
}

/** 出荷実績を計上する。計上すると在庫が減り、取り消せない。 */
export async function postShipment(_prev: FormState, form: FormData): Promise<FormState> {
  const result = await mutate(PostShipmentDocument, {
    input: { shipmentRequestId: str(form, "shipment_request_id"), shippedOn: str(form, "shipped_on") },
  });
  return settle(result, (d) => d.postShipment, pathsFor(form));
}

/** 受注側の取消。admin に限る。 */
export async function cancelSalesOrder(_prev: FormState, form: FormData): Promise<FormState> {
  const result = await mutate(CancelSalesOrderDocument, { input: { salesOrderId: str(form, "sales_order_id") } });
  return settle(result, (d) => d.cancelSalesOrder, pathsFor(form));
}

/** 発注側の取消依頼の審査を承認する (受注を取り消す)。admin に限る。 */
export async function approveCancellationReview(_prev: FormState, form: FormData): Promise<FormState> {
  const result = await mutate(ApproveCancellationReviewDocument, {
    input: { cancellationReviewId: str(form, "cancellation_review_id") },
  });
  return settle(result, (d) => d.approveCancellationReview, pathsFor(form));
}

/** 発注側の取消依頼の審査を却下する (受注を続ける)。admin に限る。 */
export async function rejectCancellationReview(_prev: FormState, form: FormData): Promise<FormState> {
  const result = await mutate(RejectCancellationReviewDocument, {
    input: { cancellationReviewId: str(form, "cancellation_review_id") },
  });
  return settle(result, (d) => d.rejectCancellationReview, pathsFor(form));
}
