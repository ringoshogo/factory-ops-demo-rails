import { sortColumns, type Column } from "@/components/columns";
import { FilterBar } from "@/components/filter-bar";
import { FilterMenu } from "@/components/filter-menu";
import { ListError } from "@/components/list-error";
import { ListTabs } from "@/components/list-tabs";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { ShipmentRequestTable } from "@/components/shipment-request-table";
import { SupplierShipmentRequestsDocument, type ShipmentRequestOrderField } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { nodesOf, toParams, type SearchParams } from "@/lib/list";
import {
  parseShipmentRequestList,
  SHIPMENT_REQUEST_TABS,
  shipmentRequestListVariables,
  shipmentStatusOptions,
  type ShipmentRequestTab,
} from "@/lib/shipment-request-list";
import { SHIPMENT_REQUEST_STATUS } from "@/lib/statuses";

const ALL = { value: "", label: "すべて" };

// 並べ替えの見出しは API の orderBy の field から作る
const SORT = sortColumns<ShipmentRequestOrderField>(
  { ORDER_NO: "受注番号", CUSTOMER_NAME: "取引先", DUE_DATE: "出荷期限", PLANNED_DATE: "出荷予定日", STATUS: "状況" },
  { CUSTOMER_NAME: { truncate: true } },
);

const COLUMNS: Column<ShipmentRequestOrderField>[] = [
  SORT.ORDER_NO,
  SORT.CUSTOMER_NAME,
  SORT.DUE_DATE,
  SORT.PLANNED_DATE,
  { key: "quantity", label: "数量", numeric: true },
  SORT.STATUS,
  { key: "actions", label: "操作" },
];

// 出荷依頼一覧。受注を全量で引き当てると出荷依頼ができ、ここで出荷指示と出荷実績の計上を行う。
// 1 ページずつ読み、並べ替え・絞り込み・件数はサーバーが行う
export default async function ShipmentRequestsPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = toParams(await searchParams);
  const q = parseShipmentRequestList(params);
  const result = await query(SupplierShipmentRequestsDocument, shipmentRequestListVariables(q, params));

  const error = result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.kind === "error" ? result.message : null;
  const data = result.kind === "ok" ? result.data.supplier : null;
  const counts: Record<ShipmentRequestTab, number> | null = data && {
    all: data.all.totalCount,
    open: data.open.totalCount,
    shipped: data.shipped.totalCount,
    cancelled: data.cancelled.totalCount,
  };

  return (
    <section className="space-y-5">
      <PageHeader title="出荷依頼" divider={false} />

      <ListTabs label="出荷依頼のまとまり" tabs={SHIPMENT_REQUEST_TABS} current={q.tab} counts={counts} />

      <FilterBar count={data ? data.shipmentRequests.totalCount : null}>
        <FilterMenu
          label="状況"
          icon="shipping"
          param="status"
          value={q.status ?? ""}
          options={[ALL, ...shipmentStatusOptions(q.tab).map((s) => ({ value: s, label: SHIPMENT_REQUEST_STATUS[s].label }))]}
        />
      </FilterBar>

      {error || !data ? (
        <ListError>{error}</ListError>
      ) : (
        <>
          <ShipmentRequestTable
            columns={COLUMNS}
            sort={q.sort}
            businessDate={data.dashboard.businessDate}
            rows={nodesOf(data.shipmentRequests).map((r) => ({
              id: r.id,
              dueDate: r.dueDate,
              status: r.status,
              salesOrder: r.salesOrder,
              customer: r.customer,
              quantity: r.lines.reduce((sum, l) => sum + l.quantity, 0),
              plannedDate: r.instruction?.plannedDate ?? null,
            }))}
          />
          <Pagination pageInfo={data.shipmentRequests.pageInfo} />
        </>
      )}
    </section>
  );
}
