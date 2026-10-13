import type { SalesOrderStatus, ShipmentRequestStatus } from "@/lib/graphql/generated";

/**
 * 受注の画面に出す操作を、受注の状況と出荷依頼の状況から決める。API も同じ規則で拒むが、押せるのに通らないボタンを
 * 出さないために、画面の「できること」はここでだけ決める (受注詳細・かんばん・出荷依頼一覧)。
 *
 * 引当は受注の単位で行い、全量を引き当てると出荷依頼 (出荷待ち) ができる。出荷指示を作ると出荷依頼が出荷指示済になり、
 * 出荷実績を計上すると受注が出荷済になる。取消の依頼を受けた受注の出荷依頼は出荷停止中になり、出荷の操作を出さない。
 */
export type OrderForFlow = {
  status: SalesOrderStatus;
  shipmentRequest: { status: ShipmentRequestStatus } | null;
};

export type CardAction = "allocate" | "instruct" | "ship";

const ALLOCATABLE: readonly SalesOrderStatus[] = ["RECEIVED", "PARTIALLY_ALLOCATED"];
// 出荷も検収も取消もしていない受注だけを、受注側から取り消せる
const CANCELLABLE: readonly SalesOrderStatus[] = ["AWAITING_PART_MATCH", "RECEIVED", "PARTIALLY_ALLOCATED", "ALLOCATED"];

export function canAllocate(order: OrderForFlow): boolean {
  return ALLOCATABLE.includes(order.status);
}

export function canInstruct(order: OrderForFlow): boolean {
  return order.status === "ALLOCATED" && order.shipmentRequest?.status === "READY";
}

export function canShip(order: OrderForFlow): boolean {
  return order.status === "ALLOCATED" && order.shipmentRequest?.status === "INSTRUCTED";
}

/** 出荷指示を取り消せるのは、出荷実績を計上する前の出荷指示済の出荷依頼だけ。 */
export function canCancelInstruction(order: OrderForFlow): boolean {
  return canShip(order);
}

export function canCancel(order: OrderForFlow): boolean {
  return CANCELLABLE.includes(order.status);
}

/** かんばんのカードに置く主な次の操作。取消・出荷指示の取消は置かない。 */
export function nextAction(order: OrderForFlow): CardAction | null {
  if (canAllocate(order)) return "allocate";
  if (canInstruct(order)) return "instruct";
  if (canShip(order)) return "ship";
  return null;
}

/**
 * 状況のバッジに重ねる印。取消の審査は状況ではないので印で示し、受注の状況に無い出荷の段階 (出荷指示済・出荷停止中) も
 * 出荷依頼の状況から印で示す。両方あれば審査を先に出す。
 */
export function orderMark(order: OrderForFlow & { cancellationReviewPending: boolean }): string | undefined {
  if (order.cancellationReviewPending) return "取消審査中";
  if (order.status !== "ALLOCATED") return undefined;
  if (order.shipmentRequest?.status === "INSTRUCTED") return "出荷指示済";
  if (order.shipmentRequest?.status === "ON_HOLD") return "出荷停止中";
  return undefined;
}
