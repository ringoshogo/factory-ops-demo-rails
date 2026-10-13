import type { SalesOrderFilter, SalesOrderOrderField, SalesOrderStatus } from "@/lib/graphql/generated";
import { pageArgs, parseDate, parseEnumList, parseSort, single, type Sort } from "@/lib/list";
import { SALES_ORDER_STATUS_ORDER } from "@/lib/statuses";

/**
 * 受注一覧の URL の値を、GraphQL の変数に写す。サーバー部品 (一覧) とクライアント部品 (タブ・絞り込み) の両方が
 * import するので、next/headers を読み込まない。
 *
 * タブは状況のまとまりで、URL の `tab` に持つ。状況の絞り込み (`status`) はタブのまとまりの中の 1 つで、
 * タブの外の状況を選んでいれば「すべて」のタブにする。タブごとの件数は、一覧と同じ取引先と受注日の絞り込みに、
 * タブの状況を足した一覧の totalCount で数える。ダッシュボードの状況ごとの件数とかんばんの列の件数も、
 * 同じ状況の絞り込みで数えるので、どれも一致する。
 */
export type SalesOrderTab = "all" | "open" | "shipped" | "inspected" | "cancelled";

export const SALES_ORDER_TABS: readonly { tab: SalesOrderTab; label: string; statuses: readonly SalesOrderStatus[] | null }[] = [
  { tab: "all", label: "すべて", statuses: null },
  { tab: "open", label: "進行中", statuses: ["AWAITING_PART_MATCH", "RECEIVED", "PARTIALLY_ALLOCATED", "ALLOCATED"] },
  { tab: "shipped", label: "出荷済", statuses: ["SHIPPED"] },
  { tab: "inspected", label: "検収済", statuses: ["INSPECTED"] },
  { tab: "cancelled", label: "取消済", statuses: ["CANCELLED"] },
];

/** 出荷も検収も取消もしていない受注の状況。期限に文言を添えるかどうかを決める。 */
export const OPEN_SALES_ORDER_STATUSES = SALES_ORDER_TABS.find((t) => t.tab === "open")!.statuses!;

export const SALES_ORDER_SORT_FIELDS: readonly SalesOrderOrderField[] = [
  "ORDER_NO",
  "CUSTOMER_NAME",
  "ORDER_DATE",
  "DUE_DATE",
  "STATUS",
  "TOTAL_AMOUNT",
];

export type SalesOrderListQuery = {
  tab: SalesOrderTab;
  status: SalesOrderStatus | null;
  customerTenantId: string | null;
  from: string | null;
  to: string | null;
  sort: Sort<SalesOrderOrderField>;
};

export function parseSalesOrderList(params: URLSearchParams): SalesOrderListQuery {
  const status = parseEnumList(params, "status", SALES_ORDER_STATUS_ORDER)?.[0] ?? null;
  const requested = SALES_ORDER_TABS.find((t) => t.tab === single(params, "tab"))?.tab ?? "all";
  const statuses = tabStatuses(requested);
  const tab = status && statuses && !statuses.includes(status) ? "all" : requested;
  return {
    tab,
    status,
    customerTenantId: single(params, "customer"),
    from: parseDate(params, "from"),
    to: parseDate(params, "to"),
    sort: parseSort(params, SALES_ORDER_SORT_FIELDS),
  };
}

function tabStatuses(tab: SalesOrderTab): readonly SalesOrderStatus[] | null {
  return SALES_ORDER_TABS.find((t) => t.tab === tab)!.statuses;
}

/** 取引先と受注日の絞り込み。タブと状況を除いた部分で、タブの件数の土台になる。 */
function baseFilter(q: SalesOrderListQuery): SalesOrderFilter {
  return { customerTenantId: q.customerTenantId, orderDateFrom: q.from, orderDateTo: q.to };
}

/** 一覧とタブの件数の変数。 */
export function salesOrderListVariables(q: SalesOrderListQuery, params: URLSearchParams) {
  const base = baseFilter(q);
  const withTab = (tab: SalesOrderTab): SalesOrderFilter => {
    const statuses = tabStatuses(tab);
    return statuses ? { ...base, statuses: [...statuses] } : base;
  };
  return {
    ...pageArgs(params),
    orderBy: q.sort,
    filter: q.status ? { ...base, statuses: [q.status] } : withTab(q.tab),
    allFilter: withTab("all"),
    openFilter: withTab("open"),
    shippedFilter: withTab("shipped"),
    inspectedFilter: withTab("inspected"),
    cancelledFilter: withTab("cancelled"),
  };
}

/** 状況のメニューの選択肢 (タブのまとまり)。 */
export function statusOptions(tab: SalesOrderTab): readonly SalesOrderStatus[] {
  return tabStatuses(tab) ?? SALES_ORDER_STATUS_ORDER;
}
