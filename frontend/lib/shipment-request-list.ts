import type { ShipmentRequestFilter, ShipmentRequestOrderField, ShipmentRequestStatus } from "@/lib/graphql/generated";
import { pageArgs, parseEnumList, parseSort, single, type Sort } from "@/lib/list";
import { SHIPMENT_REQUEST_STATUS_ORDER } from "@/lib/statuses";

/**
 * 出荷依頼一覧の URL の値を、GraphQL の変数に写す。形は受注一覧 (lib/sales-order-list.ts) と同じで、タブは状況の
 * まとまり、状況の絞り込みはタブのまとまりの中の 1 つ、タブごとの件数はタブの状況で絞った一覧の totalCount で数える。
 */
export type ShipmentRequestTab = "all" | "open" | "shipped" | "cancelled";

export const SHIPMENT_REQUEST_TABS: readonly {
  tab: ShipmentRequestTab;
  label: string;
  statuses: readonly ShipmentRequestStatus[] | null;
}[] = [
  { tab: "all", label: "すべて", statuses: null },
  { tab: "open", label: "未出荷", statuses: ["READY", "INSTRUCTED", "ON_HOLD"] },
  { tab: "shipped", label: "出荷済", statuses: ["SHIPPED"] },
  { tab: "cancelled", label: "取消済", statuses: ["CANCELLED"] },
];

/** 出荷も取消もしていない出荷依頼の状況。期限に文言を添えるかどうかを決める。 */
export const OPEN_SHIPMENT_REQUEST_STATUSES = SHIPMENT_REQUEST_TABS.find((t) => t.tab === "open")!.statuses!;

export const SHIPMENT_REQUEST_SORT_FIELDS: readonly ShipmentRequestOrderField[] = ["DUE_DATE"];

export type ShipmentRequestListQuery = {
  tab: ShipmentRequestTab;
  status: ShipmentRequestStatus | null;
  sort: Sort<ShipmentRequestOrderField>;
};

function tabStatuses(tab: ShipmentRequestTab): readonly ShipmentRequestStatus[] | null {
  return SHIPMENT_REQUEST_TABS.find((t) => t.tab === tab)!.statuses;
}

export function parseShipmentRequestList(params: URLSearchParams): ShipmentRequestListQuery {
  const status = parseEnumList(params, "status", SHIPMENT_REQUEST_STATUS_ORDER)?.[0] ?? null;
  const requested = SHIPMENT_REQUEST_TABS.find((t) => t.tab === single(params, "tab"))?.tab ?? "all";
  const statuses = tabStatuses(requested);
  const tab = status && statuses && !statuses.includes(status) ? "all" : requested;
  return { tab, status, sort: parseSort(params, SHIPMENT_REQUEST_SORT_FIELDS) };
}

/** 一覧とタブの件数の変数。 */
export function shipmentRequestListVariables(q: ShipmentRequestListQuery, params: URLSearchParams) {
  const withTab = (tab: ShipmentRequestTab): ShipmentRequestFilter => {
    const statuses = tabStatuses(tab);
    return statuses ? { statuses: [...statuses] } : {};
  };
  return {
    ...pageArgs(params),
    orderBy: q.sort,
    filter: q.status ? { statuses: [q.status] } : withTab(q.tab),
    allFilter: withTab("all"),
    openFilter: withTab("open"),
    shippedFilter: withTab("shipped"),
    cancelledFilter: withTab("cancelled"),
  };
}

/** 状況のメニューの選択肢 (タブのまとまり)。 */
export function shipmentStatusOptions(tab: ShipmentRequestTab): readonly ShipmentRequestStatus[] {
  return tabStatuses(tab) ?? SHIPMENT_REQUEST_STATUS_ORDER;
}
