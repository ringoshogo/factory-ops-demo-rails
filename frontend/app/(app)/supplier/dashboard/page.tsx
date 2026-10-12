import { Link, TextLink } from "@/components/app-link";
import { DueDate } from "@/components/date-text";
import { ErrorNotice } from "@/components/error-notice";
import { KanbanBoard, type BoardCard, type BoardColumn } from "@/components/kanban-board";
import { PageHeader } from "@/components/page-header";
import { StatusBadge } from "@/components/status-badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatBusinessDate } from "@/lib/dates";
import { sumAmounts, yen } from "@/lib/format";
import {
  SupplierDashboardDocument,
  SupplierKanbanDocument,
  type SalesOrderStatus,
  type SupplierKanbanQuery,
} from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { nodesOf } from "@/lib/list";
import { SALES_ORDER_STATUS, SALES_ORDER_STATUS_ORDER, SHIPMENT_REQUEST_STATUS } from "@/lib/statuses";

type Kanban = SupplierKanbanQuery["supplier"];

// かんばんの列の別名。SupplierKanban.graphql の別名と同じ名前で、状況の並びと 1 対 1 にする
const KANBAN_ALIASES: Record<SalesOrderStatus, keyof Kanban> = {
  AWAITING_PART_MATCH: "awaitingPartMatch",
  RECEIVED: "received",
  PARTIALLY_ALLOCATED: "partiallyAllocated",
  ALLOCATED: "allocated",
  SHIPPED: "shipped",
  INSPECTED: "inspected",
  CANCELLED: "cancelled",
};

// ダッシュボードに出す安全在庫を下回る在庫の行の数。残りは在庫の画面の切り替えで見る
const ALERT_PREVIEW = 10;

// 受注側のダッシュボード。どの数字からも、その数字を数えたのと同じ条件で絞った一覧へ行ける (数字だけを見せると、
// 何を数えたのかが読めない)。状況ごとの件数・受注一覧のタブ・かんばんの列は、同じ状況の絞り込みで数える
export default async function SupplierDashboardPage() {
  const [dashboard, kanban] = await Promise.all([query(SupplierDashboardDocument), query(SupplierKanbanDocument)]);
  if (dashboard.kind !== "ok" || kanban.kind !== "ok") {
    const failed = dashboard.kind !== "ok" ? dashboard : kanban;
    return (
      <ErrorNotice data-testid="list-error">{failed.kind === "error" ? failed.message : UNREACHABLE_MESSAGE}</ErrorNotice>
    );
  }

  const view = dashboard.data.supplier.dashboard;
  const businessDate = view.businessDate;
  const counts = new Map(view.salesOrderCounts.map((c) => [c.status, c.count]));
  const columns: BoardColumn[] = SALES_ORDER_STATUS_ORDER.map((status) => {
    const list = kanban.data.supplier[KANBAN_ALIASES[status]];
    return { status, total: list.totalCount, cards: nodesOf(list).map(toCard) };
  });
  const alerts = view.stocksBelowSafetyStock;
  const dueSoon = view.shipmentRequestsDueSoon;

  return (
    // 区画の間は 32px
    <section className="flex flex-col gap-8">
      <PageHeader
        title="ダッシュボード"
        description={
          <>
            業務日{" "}
            <time dateTime={businessDate} data-testid="business-date">
              {formatBusinessDate(businessDate)}
            </time>
          </>
        }
      />

      {/* KPI は 1 つの面を区切り線で 3 つに分ける。1024px 未満は縦に並べる */}
      <div className="grid lg:grid-cols-3">
        <Kpi
          href="/supplier/shipment-requests?tab=open&sort=due_date&dir=asc"
          testId="due-soon-link"
          label="出荷期限が近い出荷依頼"
          value={<span data-testid="due-soon-count">{dueSoon.length}</span>}
          unit="件"
        >
          今日から 7 日以内・未出荷
        </Kpi>
        <Kpi
          href="/supplier/stocks?below=1"
          testId="stock-alerts-link"
          label="在庫アラート"
          value={<span data-testid="stock-alerts-count">{alerts.length}</span>}
          unit="品目"
        >
          <Chip>要補充</Chip>
          有効在庫が安全在庫を下回る
        </Kpi>
        <Kpi
          href="/supplier/billing"
          testId="unbilled-link"
          label="未請求の金額"
          value={<span data-testid="unbilled-total">{yen(view.unbilledTotal)}</span>}
          unit="円"
        >
          検収済で締めていない明細（税抜き）
        </Kpi>
      </div>

      <div>
        <SectionHeading>受注の状況</SectionHeading>
        {/* 状況ごとの件数。それぞれの数字から、同じ状況で絞った受注一覧へ行く */}
        <ul className="flex flex-wrap gap-x-6 gap-y-3">
          {SALES_ORDER_STATUS_ORDER.map((status) => (
            <li key={status}>
              <Link
                href={`/supplier/sales-orders?status=${status}`}
                data-testid="status-count"
                data-status={status}
                className="group flex items-center gap-2"
              >
                <StatusBadge style={SALES_ORDER_STATUS[status]} />
                <span className="group-hover:text-link text-lg font-semibold tabular-nums">
                  <span data-testid="status-count-value">{counts.get(status) ?? 0}</span>
                  <span className="text-muted-foreground ml-0.5 text-xs font-medium">件</span>
                </span>
              </Link>
            </li>
          ))}
        </ul>
      </div>

      <div>
        <SectionHeading>受注の流れ</SectionHeading>
        <KanbanBoard columns={columns} businessDate={businessDate} />
      </div>

      <div>
        <SectionHeading>
          在庫アラート
          {alerts.length > ALERT_PREVIEW && (
            <span className="text-muted-foreground ml-auto text-[13px] font-normal">
              {alerts.length} 品目のうち不足の大きい {ALERT_PREVIEW} 件
              <TextLink href="/supplier/stocks?below=1" className="ml-2 font-medium">
                在庫の画面で見る
              </TextLink>
            </span>
          )}
        </SectionHeading>
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>品目コード</TableHead>
                <TableHead>品名</TableHead>
                <TableHead numeric>有効在庫</TableHead>
                <TableHead numeric>安全在庫</TableHead>
                <TableHead numeric>不足</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {alerts.length === 0 && (
                <TableRow>
                  <TableCell colSpan={5} className="text-muted-foreground py-8 text-center">
                    安全在庫を下回る品目はありません
                  </TableCell>
                </TableRow>
              )}
              {/* 不足の大きい順に見せる (全件は在庫の画面で見られる)。行の高さは 48px */}
              {[...alerts]
                .sort((a, b) => a.available - a.safetyStock - (b.available - b.safetyStock))
                .slice(0, ALERT_PREVIEW)
                .map((row) => (
                  <TableRow key={row.item.id} data-testid="stock-alert-row">
                    <TableCell truncate className="text-muted-foreground h-12">
                      {row.item.code}
                    </TableCell>
                    <TableCell truncate className="h-12">
                      {row.item.name}
                    </TableCell>
                    <TableCell numeric className="h-12">
                      {row.available}
                    </TableCell>
                    <TableCell numeric className="h-12">
                      {row.safetyStock}
                    </TableCell>
                    {/* 不足数は注意の色・600 */}
                    <TableCell numeric className="text-caution h-12 font-semibold">
                      {row.safetyStock - row.available}
                    </TableCell>
                  </TableRow>
                ))}
            </TableBody>
          </Table>
        </div>
      </div>

      <div>
        <SectionHeading>出荷期限が近い出荷依頼</SectionHeading>
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>受注番号</TableHead>
                <TableHead>取引先</TableHead>
                <TableHead>出荷期限</TableHead>
                <TableHead>状況</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {dueSoon.length === 0 && (
                <TableRow>
                  <TableCell colSpan={4} className="text-muted-foreground py-8 text-center">
                    7 日以内に期限が来る出荷依頼はありません
                  </TableCell>
                </TableRow>
              )}
              {dueSoon.map((request) => (
                <TableRow key={request.id} data-testid="due-soon-row">
                  <TableCell className="h-12">
                    <TextLink href={`/supplier/sales-orders/${request.salesOrder.id}`} className="font-semibold">
                      {request.salesOrder.orderNo}
                    </TextLink>
                  </TableCell>
                  <TableCell truncate className="h-12">
                    {request.customer.name}
                  </TableCell>
                  <TableCell className="h-12">
                    <DueDate due={request.dueDate} open businessDate={businessDate} />
                  </TableCell>
                  <TableCell className="h-12">
                    <StatusBadge style={SHIPMENT_REQUEST_STATUS[request.status]} value={request.status} />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      </div>
    </section>
  );
}

function toCard(order: NonNullable<NonNullable<Kanban["received"]["nodes"]>[number]>): BoardCard {
  return {
    id: order.id,
    orderNo: order.orderNo,
    dueDate: order.dueDate,
    status: order.status,
    cancellationReviewPending: order.cancellationReviewPending,
    customerName: order.customer.name,
    // 品番照合待ちの明細は単価が無いので、合計を出さない
    total: order.lines.every((l) => l.unitPrice)
      ? yen(sumAmounts(order.lines.map((l) => BigInt(l.unitPrice!) * BigInt(l.quantity))))
      : null,
    shipmentRequest: order.shipmentRequest,
  };
}

/** 区画の見出し 2 (16px・600)。右に補助の文字やリンクを置ける。 */
function SectionHeading({ children }: { children: React.ReactNode }) {
  return <h2 className="mb-3.5 flex flex-wrap items-baseline gap-x-2.5 gap-y-1 text-base font-semibold">{children}</h2>;
}

/** KPI の小札。固定の注記なのでニュートラルの面にする。 */
function Chip({ children }: { children: React.ReactNode }) {
  return (
    <span data-slot="kpi-chip" className="bg-neutral-chip text-foreground-2 rounded-badge px-1.5 py-px text-xs font-medium">
      {children}
    </span>
  );
}

/**
 * KPI の 1 区画。カードの枠を持たず、2 つ目からは区切り線 (--divider) で前と分ける。1024px 以上は縦の線で横に並べ、
 * 未満は横の線で縦に並べる。
 */
function Kpi({
  href,
  testId,
  label,
  value,
  unit,
  children,
}: {
  href: string;
  testId: string;
  label: string;
  value: React.ReactNode;
  unit: string;
  children: React.ReactNode;
}) {
  return (
    <Link
      href={href}
      data-testid={testId}
      data-slot="kpi"
      className="group border-divider block py-4 first:pt-0 not-first:border-t lg:px-6 lg:py-1 lg:first:pt-1 lg:first:pl-0 lg:not-first:border-t-0 lg:not-first:border-l"
    >
      <p className="text-muted-foreground group-hover:text-foreground text-[13px] font-medium">{label}</p>
      <div
        data-slot="kpi-value"
        className="mt-1.5 flex items-baseline gap-1.5 text-[32px] leading-tight font-semibold tracking-[-0.02em] tabular-nums"
      >
        {value}
        <span className="text-muted-foreground text-sm font-medium tracking-normal">{unit}</span>
      </div>
      <div className="text-muted-foreground mt-1 flex flex-wrap items-center gap-1.5 text-[13px]">{children}</div>
    </Link>
  );
}
