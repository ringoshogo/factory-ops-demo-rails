import type { PurchaseOrderFilter, PurchaseOrderOrderField, PurchaseOrderStatus } from "@/lib/graphql/generated";
import { pageArgs, parseDate, parseEnumList, parseSort, single, type Sort } from "@/lib/list";
import { PURCHASE_ORDER_STATUS_ORDER } from "@/lib/statuses";

/**
 * 発注一覧の URL の値を、GraphQL の変数に写す。サーバー部品 (一覧) とクライアント部品 (タブ・絞り込み) の両方が
 * import するので、next/headers を読み込まない。
 *
 * タブは状況のまとまりで、URL の `tab` に持つ。入荷を待つ発注は「入荷予定」のタブで見る (発注をまたいだ入荷の一覧は
 * 置かない)。状況の絞り込み (`status`) はタブのまとまりの中の 1 つで、タブの外の状況を選んでいれば「すべて」の
 * タブにする。タブごとの件数は、一覧と同じ取引先と発注日の絞り込みに、タブの状況を足した一覧の totalCount で数える。
 */
export type PurchaseOrderTab = "all" | "open" | "inbound" | "inspected" | "cancelled";

export const PURCHASE_ORDER_TABS: readonly {
  tab: PurchaseOrderTab;
  label: string;
  statuses: readonly PurchaseOrderStatus[] | null;
}[] = [
  { tab: "all", label: "すべて", statuses: null },
  { tab: "open", label: "進行中", statuses: ["SENT", "AWAITING_SUPPLIER_CONFIRMATION", "ACCEPTED"] },
  { tab: "inbound", label: "入荷予定", statuses: ["INBOUND"] },
  { tab: "inspected", label: "検収済", statuses: ["INSPECTED"] },
  { tab: "cancelled", label: "取消", statuses: ["CANCELLED", "SUPPLIER_CANCELLED"] },
];

/** 検収も取消もしていない発注の状況。希望納期に文言を添えるかどうかを決める。 */
export const OPEN_PURCHASE_ORDER_STATUSES: readonly PurchaseOrderStatus[] = [
  "SENT",
  "AWAITING_SUPPLIER_CONFIRMATION",
  "ACCEPTED",
  "INBOUND",
];

export const PURCHASE_ORDER_SORT_FIELDS: readonly PurchaseOrderOrderField[] = [
  "ORDER_NO",
  "SUPPLIER_NAME",
  "ORDER_DATE",
  "DESIRED_DELIVERY_ON",
  "STATUS",
  "TOTAL_AMOUNT",
];

export type PurchaseOrderListQuery = {
  tab: PurchaseOrderTab;
  status: PurchaseOrderStatus | null;
  supplierTenantId: string | null;
  from: string | null;
  to: string | null;
  sort: Sort<PurchaseOrderOrderField>;
};

export function parsePurchaseOrderList(params: URLSearchParams): PurchaseOrderListQuery {
  const status = parseEnumList(params, "status", PURCHASE_ORDER_STATUS_ORDER)?.[0] ?? null;
  const requested = PURCHASE_ORDER_TABS.find((t) => t.tab === single(params, "tab"))?.tab ?? "all";
  const statuses = tabStatuses(requested);
  const tab = status && statuses && !statuses.includes(status) ? "all" : requested;
  return {
    tab,
    status,
    supplierTenantId: single(params, "supplier"),
    from: parseDate(params, "from"),
    to: parseDate(params, "to"),
    sort: parseSort(params, PURCHASE_ORDER_SORT_FIELDS),
  };
}

function tabStatuses(tab: PurchaseOrderTab): readonly PurchaseOrderStatus[] | null {
  return PURCHASE_ORDER_TABS.find((t) => t.tab === tab)!.statuses;
}

/** 一覧とタブの件数の変数。取引先と発注日の絞り込みを土台にし、タブか状況の絞り込みを足す。 */
export function purchaseOrderListVariables(q: PurchaseOrderListQuery, params: URLSearchParams) {
  const base: PurchaseOrderFilter = { supplierTenantId: q.supplierTenantId, orderDateFrom: q.from, orderDateTo: q.to };
  const withTab = (tab: PurchaseOrderTab): PurchaseOrderFilter => {
    const statuses = tabStatuses(tab);
    return statuses ? { ...base, statuses: [...statuses] } : base;
  };
  return {
    ...pageArgs(params),
    orderBy: q.sort,
    filter: q.status ? { ...base, statuses: [q.status] } : withTab(q.tab),
    allFilter: withTab("all"),
    openFilter: withTab("open"),
    inboundFilter: withTab("inbound"),
    inspectedFilter: withTab("inspected"),
    cancelledFilter: withTab("cancelled"),
  };
}

/** 状況のメニューの選択肢 (タブのまとまり)。 */
export function purchaseOrderStatusOptions(tab: PurchaseOrderTab): readonly PurchaseOrderStatus[] {
  return tabStatuses(tab) ?? PURCHASE_ORDER_STATUS_ORDER;
}
