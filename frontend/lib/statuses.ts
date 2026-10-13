import type {
  ImportKind,
  ImportStatus,
  InvoiceState,
  PartnershipPermission,
  PartnershipStatus,
  PurchaseOrderStatus,
  SalesOrderStatus,
  ShipmentRequestStatus,
  StockMovementType,
} from "@/lib/graphql/generated";

/**
 * 状況の enum の値ごとの文言と色。色は 6 つの色 (受注済・一部引当・引当済・出荷指示済・出荷済・取消) だけを使い回し、
 * 色のトークンを足さない。待っている状況は灰、手当てが要る状況は黄、進んでいる状況は青、次の手前の状況は橙、
 * 終えた状況は緑、取り消した状況は赤にする。`Record<enum, …>` で書くので、API が値を足すと型検査が落ちる。
 */
export type Tone = "received" | "partial" | "allocated" | "instructed" | "shipped" | "cancelled";

export type StatusStyle = { label: string; tone: Tone };

export const SALES_ORDER_STATUS: Record<SalesOrderStatus, StatusStyle> = {
  AWAITING_PART_MATCH: { label: "品番照合待ち", tone: "partial" },
  RECEIVED: { label: "受注済", tone: "received" },
  PARTIALLY_ALLOCATED: { label: "一部引当", tone: "partial" },
  ALLOCATED: { label: "引当済", tone: "allocated" },
  SHIPPED: { label: "出荷済", tone: "shipped" },
  INSPECTED: { label: "検収済", tone: "shipped" },
  CANCELLED: { label: "取消済", tone: "cancelled" },
};

/** かんばんの列と、受注一覧の状況の選択肢の並び。業務の進む順に置く。 */
export const SALES_ORDER_STATUS_ORDER: readonly SalesOrderStatus[] = [
  "AWAITING_PART_MATCH",
  "RECEIVED",
  "PARTIALLY_ALLOCATED",
  "ALLOCATED",
  "SHIPPED",
  "INSPECTED",
  "CANCELLED",
];

export const PURCHASE_ORDER_STATUS: Record<PurchaseOrderStatus, StatusStyle> = {
  SENT: { label: "送信済み", tone: "received" },
  AWAITING_SUPPLIER_CONFIRMATION: { label: "受注側で確認中", tone: "partial" },
  ACCEPTED: { label: "受注済", tone: "allocated" },
  INBOUND: { label: "入荷予定", tone: "instructed" },
  INSPECTED: { label: "検収済", tone: "shipped" },
  CANCELLED: { label: "取消済み", tone: "cancelled" },
  SUPPLIER_CANCELLED: { label: "受注側により取消", tone: "cancelled" },
};

export const PURCHASE_ORDER_STATUS_ORDER: readonly PurchaseOrderStatus[] = [
  "SENT",
  "AWAITING_SUPPLIER_CONFIRMATION",
  "ACCEPTED",
  "INBOUND",
  "INSPECTED",
  "CANCELLED",
  "SUPPLIER_CANCELLED",
];

export const SHIPMENT_REQUEST_STATUS: Record<ShipmentRequestStatus, StatusStyle> = {
  READY: { label: "出荷待ち", tone: "allocated" },
  INSTRUCTED: { label: "出荷指示済", tone: "instructed" },
  ON_HOLD: { label: "出荷停止中", tone: "partial" },
  SHIPPED: { label: "出荷済", tone: "shipped" },
  CANCELLED: { label: "取消済", tone: "cancelled" },
};

export const SHIPMENT_REQUEST_STATUS_ORDER: readonly ShipmentRequestStatus[] = [
  "READY",
  "INSTRUCTED",
  "ON_HOLD",
  "SHIPPED",
  "CANCELLED",
];

export const IMPORT_STATUS: Record<ImportStatus, StatusStyle> = {
  QUEUED: { label: "待機中", tone: "received" },
  STAGING: { label: "置き場へ写し中", tone: "allocated" },
  APPLYING: { label: "反映中", tone: "allocated" },
  SUCCEEDED: { label: "完了", tone: "shipped" },
  PARTIALLY_FAILED: { label: "一部失敗", tone: "partial" },
  FAILED: { label: "失敗", tone: "cancelled" },
};

/** 取り込みが終わった状況。終わるまでは画面が数秒ごとに読み直す。 */
export const IMPORT_FINISHED: readonly ImportStatus[] = ["SUCCEEDED", "PARTIALLY_FAILED", "FAILED"];

export const IMPORT_KIND: Record<ImportKind, string> = { ITEMS: "品目と単価", STOCKS: "在庫" };

export const INVOICE_STATE: Record<InvoiceState, StatusStyle> = {
  DRAFT: { label: "下書き", tone: "received" },
  ISSUED: { label: "発行済み", tone: "shipped" },
};

export const PARTNERSHIP_STATUS: Record<PartnershipStatus, StatusStyle> = {
  ACTIVE: { label: "有効", tone: "shipped" },
  REVOKED: { label: "失効", tone: "cancelled" },
};

export const PERMISSION_LABEL: Record<PartnershipPermission, string> = {
  VIEW_CATALOG: "カタログを見る",
  PLACE_ORDERS: "発注する",
  VIEW_SHIPMENTS: "出荷を見る",
};

export const PERMISSION_ORDER: readonly PartnershipPermission[] = ["VIEW_CATALOG", "PLACE_ORDERS", "VIEW_SHIPMENTS"];

export const STOCK_MOVEMENT_TYPE: Record<StockMovementType, string> = {
  INBOUND: "入庫",
  OUTBOUND: "出庫",
  ALLOCATE: "引当",
  DEALLOCATE: "引当の解除",
  SHIP: "出荷",
};
