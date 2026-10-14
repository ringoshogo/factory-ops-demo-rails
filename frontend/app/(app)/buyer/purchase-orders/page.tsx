import type { ReactNode } from "react";
import { Link, TextLink } from "@/components/app-link";
import { ColumnHeads, sortColumns, sortCell, type Column } from "@/components/columns";
import { DateRangeFilter } from "@/components/date-range-filter";
import { DateText, DueDate } from "@/components/date-text";
import { FilterBar } from "@/components/filter-bar";
import { FilterMenu } from "@/components/filter-menu";
import { ListError } from "@/components/list-error";
import { ListTabs } from "@/components/list-tabs";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { StatusBadge } from "@/components/status-badge";
import { buttonVariants } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHeader, TableRow } from "@/components/ui/table";
import { totalAmountText } from "@/lib/format";
import { BuyerPurchaseOrdersDocument, type PurchaseOrderOrderField } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { nodesOf, toParams, type SearchParams } from "@/lib/list";
import {
  OPEN_PURCHASE_ORDER_STATUSES,
  PURCHASE_ORDER_TABS,
  parsePurchaseOrderList,
  purchaseOrderListVariables,
  purchaseOrderStatusOptions,
  type PurchaseOrderTab,
} from "@/lib/purchase-order-list";
import { PURCHASE_ORDER_STATUS } from "@/lib/statuses";

const ALL = { value: "", label: "すべて" };

// 並べ替えの見出しは API の orderBy の field から作る。明細の件数は API で並べられないので、ただの見出しにする
const SORT = sortColumns<PurchaseOrderOrderField>(
  {
    ORDER_NO: "発注番号",
    SUPPLIER_NAME: "取引先",
    ORDER_DATE: "発注日",
    DESIRED_DELIVERY_ON: "希望納期",
    STATUS: "状況",
    TOTAL_AMOUNT: "発注合計",
  },
  { SUPPLIER_NAME: { truncate: true }, TOTAL_AMOUNT: { numeric: true } },
);

const COLUMNS: Column<PurchaseOrderOrderField>[] = [
  SORT.ORDER_NO,
  SORT.SUPPLIER_NAME,
  SORT.ORDER_DATE,
  SORT.DESIRED_DELIVERY_ON,
  SORT.STATUS,
  { key: "lines", label: "明細", numeric: true },
  SORT.TOTAL_AMOUNT,
];

// 発注一覧。1 ページずつ読み、並べ替え・絞り込み・件数はサーバーが行う。入荷を待つ発注は「入荷予定」のタブで見て、
// 検収は発注詳細で行う
export default async function PurchaseOrdersPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = toParams(await searchParams);
  const q = parsePurchaseOrderList(params);
  const result = await query(BuyerPurchaseOrdersDocument, purchaseOrderListVariables(q, params));

  const error = result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.kind === "error" ? result.message : null;
  const data = result.kind === "ok" ? result.data.buyer : null;
  const businessDate = result.kind === "ok" ? result.data.supplier.dashboard.businessDate : null;
  const counts: Record<PurchaseOrderTab, number> | null = data && {
    all: data.all.totalCount,
    open: data.open.totalCount,
    inbound: data.inbound.totalCount,
    inspected: data.inspected.totalCount,
    cancelled: data.cancelled.totalCount,
  };
  const suppliers = data?.suppliers.map((s) => s.supplier) ?? [];

  return (
    <section className="space-y-5">
      <PageHeader title="発注一覧" divider={false}>
        <Link href="/buyer/purchase-orders/new" className={buttonVariants()}>
          発注を登録
        </Link>
      </PageHeader>

      <ListTabs label="発注のまとまり" tabs={PURCHASE_ORDER_TABS} current={q.tab} counts={counts} />

      <FilterBar count={data ? data.purchaseOrders.totalCount : null}>
        <FilterMenu
          label="状況"
          icon="status"
          param="status"
          value={q.status ?? ""}
          options={[
            ALL,
            ...purchaseOrderStatusOptions(q.tab).map((s) => ({ value: s, label: PURCHASE_ORDER_STATUS[s].label })),
          ]}
        />
        <FilterMenu
          label="取引先"
          icon="customer"
          param="supplier"
          value={q.supplierTenantId ?? ""}
          options={[ALL, ...suppliers.map((s) => ({ value: s.id, label: s.name }))]}
        />
        <DateRangeFilter label="発注日" from={q.from ?? ""} to={q.to ?? ""} businessDate={businessDate} />
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
                {nodesOf(data.purchaseOrders).length === 0 && (
                  <TableRow data-testid="empty-row">
                    <TableCell colSpan={COLUMNS.length} className="text-muted-foreground py-8 text-center">
                      該当する発注がありません
                    </TableCell>
                  </TableRow>
                )}
                {nodesOf(data.purchaseOrders).map((o) => {
                  const content: Record<string, ReactNode> = {
                    ORDER_NO: (
                      <TextLink href={`/buyer/purchase-orders/${o.id}`} className="rounded-sm font-semibold">
                        {o.orderNo}
                      </TextLink>
                    ),
                    SUPPLIER_NAME: o.supplier.name,
                    ORDER_DATE: <DateText iso={o.orderDate} businessDate={businessDate} />,
                    DESIRED_DELIVERY_ON: (
                      <DueDate
                        due={o.desiredDeliveryOn}
                        open={OPEN_PURCHASE_ORDER_STATUSES.includes(o.status)}
                        businessDate={businessDate}
                      />
                    ),
                    STATUS: (
                      <StatusBadge
                        style={PURCHASE_ORDER_STATUS[o.status]}
                        value={o.status}
                        mark={o.cancellationPending ? "取消依頼中" : undefined}
                      />
                    ),
                    lines: `${o.lines.length} 件`,
                    TOTAL_AMOUNT: totalAmountText(o.totalAmount, "purchaseOrder", o.status),
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
          <Pagination pageInfo={data.purchaseOrders.pageInfo} />
        </>
      )}
    </section>
  );
}
