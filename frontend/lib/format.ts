import type { PurchaseOrderStatus, PurchaseOrderTimelineKind, SalesOrderStatus } from "@/lib/graphql/generated";
import { CANCELLED_PURCHASE_ORDER_STATUSES, CANCELLED_SALES_ORDER_STATUSES } from "@/lib/statuses";

/**
 * 数値と金額の表示 (3 桁区切り)。サーバー部品とクライアント部品の両方が使う。
 *
 * 金額は API が BigInt を文字列で返すので、Number に直さず BigInt のまま区切る。Number は 2^53 を超えた値を丸める。
 */
export const formatNumber = (n: number) => n.toLocaleString("ja-JP");

/** 金額 (円)。API の BigInt の文字列を受ける。 */
export function yen(amount: string | bigint): string {
  return BigInt(amount).toLocaleString("ja-JP");
}

/** 合計金額の空の理由。受注は品番照合待ちの明細を、発注は受注確定の前の明細を含むと、API が合計を空で返す。 */
const PENDING_TOTAL = { salesOrder: "照合待ち", purchaseOrder: "確定待ち" } as const;

type TotalStatus = { salesOrder: SalesOrderStatus; purchaseOrder: PurchaseOrderStatus };

const CANCELLED: { [K in keyof TotalStatus]: readonly TotalStatus[K][] } = {
  salesOrder: CANCELLED_SALES_ORDER_STATUSES,
  purchaseOrder: CANCELLED_PURCHASE_ORDER_STATUSES,
};

/**
 * 受注と発注の合計金額 (税抜) の表示。API の totalAmount だけから出し、画面で明細から足さない。
 * 単価の無い明細を 0 として一部の合計を出すと、画面ごとに合計が食い違う。空なら金額の代わりに空の理由を出す。
 * 待っている間に取り消した伝票は、もう照合も確定も待たないので「取消」と出す。合計があれば、取り消した伝票でも金額を出す
 * (流用元と同じく、単価の決まった伝票は取り消しても合計を持つ。docs/architecture/context-map.md「発注の連結と品番の照合」)。
 */
export function totalAmountText<K extends keyof TotalStatus>(total: string | null, kind: K, status: TotalStatus[K]): string {
  if (total !== null) return `${yen(total)} 円`;
  return isCancelled(kind, status) ? "取消" : PENDING_TOTAL[kind];
}

/** 伝票を取り消したか。取り消した伝票は照合も確定も待たないので、合計の欄と明細の行に待ちの文言を出さない。 */
export function isCancelled<K extends keyof TotalStatus>(kind: K, status: TotalStatus[K]): boolean {
  return CANCELLED[kind].includes(status);
}

/** 明細の待ちの文言。受注は品目の無い (品番照合待ちの) 明細に、発注は品目名の写しの無い (受注確定の前の) 明細に出す。 */
const PENDING_LINE = { salesOrder: "品番照合待ち", purchaseOrder: "受注側の確定待ち" } as const;

/** 待っている間に取り消した伝票の明細の文言。品目名の欄に何が無いかと、取り消したのでもう待たないことを 1 つで言う。 */
const CANCELLED_LINE = { salesOrder: "品番未照合（取消）", purchaseOrder: "未確定（取消）" } as const;

/**
 * 受注詳細と発注詳細の、品目名の欄が空の明細の文言。合計の欄 (totalAmountText) と同じ取消の状況の集合で分け、
 * 合計の欄が「取消」の伝票の明細に待ちの文言を出さない (docs/architecture/context-map.md「発注の連結と品番の照合」)。
 */
export function pendingLineText<K extends keyof TotalStatus>(kind: K, status: TotalStatus[K]): string {
  return isCancelled(kind, status) ? CANCELLED_LINE[kind] : PENDING_LINE[kind];
}

/** 発注の進みの出来事の名前。`Record<enum, …>` で書くので、API が出来事を足すと型検査が落ちる。 */
export const PURCHASE_ORDER_TIMELINE_LABEL: Record<PurchaseOrderTimelineKind, string> = {
  ORDERED: "発注登録",
  PART_MATCH_PENDING: "品番照合待ち",
  ACCEPTED: "受注確定",
  CANCELLATION_REQUESTED: "取消依頼",
  CANCELLATION_APPROVED: "取消の承認",
  CANCELLATION_REJECTED: "取消の却下",
  SUPPLIER_CANCELLED: "受注側の取消",
  SHIPPED: "出荷",
  INSPECTED: "検収",
  INVOICE_RECEIVED: "請求書の受領",
};

const CANCELLATION_TIMELINE_KINDS: readonly PurchaseOrderTimelineKind[] = [
  "CANCELLATION_APPROVED",
  "CANCELLATION_REJECTED",
  "SUPPLIER_CANCELLED",
];

/**
 * 取消の回答と受注側の取消の出来事か。これらは、取り消した伝票の明細の文言 (pendingLineText) と同じ控えめの色で出す。
 * 取消依頼は発注側の操作で、まだ取り消していないので含めない。
 */
export function isCancellationEvent(kind: PurchaseOrderTimelineKind): boolean {
  return CANCELLATION_TIMELINE_KINDS.includes(kind);
}
