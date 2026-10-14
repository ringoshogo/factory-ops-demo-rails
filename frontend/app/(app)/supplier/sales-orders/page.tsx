import type { ReactNode } from "react";
import { TextLink } from "@/components/app-link";
import { DateRangeFilter } from "@/components/date-range-filter";
import { DateText, DueDate } from "@/components/date-text";
import { FilterBar } from "@/components/filter-bar";
import { FilterMenu } from "@/components/filter-menu";
import { ListError } from "@/components/list-error";
import { ListTabs } from "@/components/list-tabs";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { ColumnHeads, sortColumns, sortCell, type Column } from "@/components/columns";
import { StatusBadge } from "@/components/status-badge";
import { Table, TableBody, TableCell, TableHeader, TableRow } from "@/components/ui/table";
import { totalAmountText } from "@/lib/format";
import { SupplierSalesOrdersDocument, type SalesOrderOrderField } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { nodesOf, toParams, type SearchParams } from "@/lib/list";
import {
  OPEN_SALES_ORDER_STATUSES,
  parseSalesOrderList,
  SALES_ORDER_TABS,
  salesOrderListVariables,
  statusOptions,
  type SalesOrderTab,
} from "@/lib/sales-order-list";
import { SALES_ORDER_STATUS } from "@/lib/statuses";

const ALL = { value: "", label: "すべて" };

// 並べ替えの見出しは API の orderBy の field から作る
const SORT = sortColumns<SalesOrderOrderField>(
  {
    ORDER_NO: "受注番号",
    CUSTOMER_NAME: "取引先",
    ORDER_DATE: "受注日",
    DUE_DATE: "希望納期",
    STATUS: "状況",
    TOTAL_AMOUNT: "受注合計",
  },
  { CUSTOMER_NAME: { truncate: true }, TOTAL_AMOUNT: { numeric: true } },
);

const COLUMNS: Column<SalesOrderOrderField>[] = [
  SORT.ORDER_NO,
  SORT.CUSTOMER_NAME,
  SORT.ORDER_DATE,
  SORT.DUE_DATE,
  SORT.STATUS,
  SORT.TOTAL_AMOUNT,
];

// 受注一覧。1 ページずつ読み、並べ替え・絞り込み・件数はサーバーが行う。絞り込みは URL に載せ、共有や再読み込みで同じ画面に戻る
export default async function SalesOrdersPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = toParams(await searchParams);
  const q = parseSalesOrderList(params);
  const result = await query(SupplierSalesOrdersDocument, salesOrderListVariables(q, params));

  const error = result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.kind === "error" ? result.message : null;
  const data = result.kind === "ok" ? result.data.supplier : null;
  const businessDate = data?.dashboard.businessDate ?? null;
  const counts: Record<SalesOrderTab, number> | null = data && {
    all: data.all.totalCount,
    open: data.open.totalCount,
    shipped: data.shipped.totalCount,
    inspected: data.inspected.totalCount,
    cancelled: data.cancelled.totalCount,
  };
  const customers = data?.partnerships.map((p) => p.buyer) ?? [];

  return (
    <section className="space-y-5">
      <PageHeader title="受注一覧" divider={false} />

      <ListTabs label="受注のまとまり" tabs={SALES_ORDER_TABS} current={q.tab} counts={counts} />

      <FilterBar count={data ? data.salesOrders.totalCount : null}>
        <FilterMenu
          label="状況"
          icon="status"
          param="status"
          value={q.status ?? ""}
          options={[ALL, ...statusOptions(q.tab).map((s) => ({ value: s, label: SALES_ORDER_STATUS[s].label }))]}
        />
        <FilterMenu
          label="取引先"
          icon="customer"
          param="customer"
          value={q.customerTenantId ?? ""}
          options={[ALL, ...dedupe(customers).map((c) => ({ value: c.id, label: c.name }))]}
        />
        <DateRangeFilter label="受注日" from={q.from ?? ""} to={q.to ?? ""} businessDate={businessDate} />
      </FilterBar>

      {error || !data ? (
        <ListError>{error}</ListError>
      ) : (
        <>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <ColumnHeads columns={COLUMNS} state={q.sort} />
                </TableRow>
              </TableHeader>
              <TableBody>
                {nodesOf(data.salesOrders).length === 0 && (
                  <TableRow data-testid="empty-row">
                    <TableCell colSpan={COLUMNS.length} className="text-muted-foreground py-8 text-center">
                      該当する受注がありません
                    </TableCell>
                  </TableRow>
                )}
                {nodesOf(data.salesOrders).map((o) => {
                  const content: Record<string, ReactNode> = {
                    ORDER_NO: (
                      <TextLink href={`/supplier/sales-orders/${o.id}`} className="rounded-sm font-semibold">
                        {o.orderNo}
                      </TextLink>
                    ),
                    CUSTOMER_NAME: o.customer.name,
                    ORDER_DATE: <DateText iso={o.orderDate} businessDate={businessDate} />,
                    DUE_DATE: (
                      <DueDate due={o.dueDate} open={OPEN_SALES_ORDER_STATUSES.includes(o.status)} businessDate={businessDate} />
                    ),
                    STATUS: (
                      <StatusBadge
                        style={SALES_ORDER_STATUS[o.status]}
                        value={o.status}
                        mark={o.cancellationReviewPending ? "取消審査中" : undefined}
                      />
                    ),
                    TOTAL_AMOUNT: totalAmountText(o.totalAmount, "salesOrder"),
                  };
                  return (
                    <TableRow key={o.id} data-testid="list-row">
                      {COLUMNS.map((c) => (
                        <TableCell key={c.key} numeric={c.numeric} truncate={c.truncate} {...sortCell(c, q.sort)}>
                          {content[c.key]}
                        </TableCell>
                      ))}
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
          <Pagination pageInfo={data.salesOrders.pageInfo} />
        </>
      )}
    </section>
  );
}

/** 同じ取引先と、失効の後に結び直した取引関係は、取引先の選択肢を 1 つにまとめる。 */
function dedupe<T extends { id: string }>(rows: readonly T[]): T[] {
  return [...new Map(rows.map((r) => [r.id, r])).values()];
}
