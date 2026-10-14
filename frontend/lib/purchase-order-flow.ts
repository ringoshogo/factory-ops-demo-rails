import type { PurchaseOrderStatus } from "@/lib/graphql/generated";

/**
 * 発注の画面に出す操作を、発注の状況から決める。押せるのに通らないボタンを出さないために、画面の「できること」は
 * ここでだけ決める (発注詳細)。
 */
export type PurchaseOrderForFlow = {
  status: PurchaseOrderStatus;
  cancellationPending: boolean;
};

// 取消を依頼できる状況。出荷の前 (受注側が確定する前と、確定して出荷を待つ間) だけ。API は出荷した後の依頼も受け付けるが、
// 出荷済の受注への依頼は受注側が必ず却下するので、却下だけが返る操作を入荷予定の発注に見せない (docs/architecture/context-map.md「取消の流れ」)
const CANCELLATION_REQUESTABLE: readonly PurchaseOrderStatus[] = ["SENT", "AWAITING_SUPPLIER_CONFIRMATION", "ACCEPTED"];

/** 取消を依頼できるか。回答を待つ依頼があれば、重ねて依頼させない。 */
export function canRequestCancellation(order: PurchaseOrderForFlow): boolean {
  return CANCELLATION_REQUESTABLE.includes(order.status) && !order.cancellationPending;
}
