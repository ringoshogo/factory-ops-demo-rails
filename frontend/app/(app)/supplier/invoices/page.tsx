import { TextLink } from "@/components/app-link";
import { DateText } from "@/components/date-text";
import { FilterBar } from "@/components/filter-bar";
import { ListError } from "@/components/list-error";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { StatusBadge } from "@/components/status-badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { yen } from "@/lib/format";
import { SupplierInvoicesDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { nodesOf, pageArgs, toParams, type SearchParams } from "@/lib/list";
import { INVOICE_STATE } from "@/lib/statuses";

// 請求書の一覧 (下書きと発行済み)。1 ページずつ読む
export default async function InvoicesPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = toParams(await searchParams);
  const result = await query(SupplierInvoicesDocument, pageArgs(params));
  const error = result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.kind === "error" ? result.message : null;
  const data = result.kind === "ok" ? result.data.supplier : null;
  const businessDate = data?.dashboard.businessDate ?? null;
  const rows = data ? nodesOf(data.invoices) : [];

  return (
    <section className="space-y-5">
      <PageHeader title="請求書" />
      <FilterBar count={data ? data.invoices.totalCount : null}>{null}</FilterBar>
      {error || !data ? (
        <ListError>{error}</ListError>
      ) : (
        <>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>請求書番号</TableHead>
                  <TableHead>取引先</TableHead>
                  <TableHead>請求期間</TableHead>
                  <TableHead>状況</TableHead>
                  <TableHead>発行日時</TableHead>
                  <TableHead numeric>合計（税込み）</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.length === 0 && (
                  <TableRow data-testid="empty-row">
                    <TableCell colSpan={6} className="text-muted-foreground py-8 text-center">
                      請求書はありません
                    </TableCell>
                  </TableRow>
                )}
                {rows.map((invoice) => (
                  <TableRow key={invoice.id} data-testid="list-row">
                    <TableCell>
                      {/* 下書きは番号を持たないので、番号の代わりに「下書き」から詳細へ移る */}
                      <TextLink href={`/supplier/invoices/${invoice.id}`} className="rounded-sm font-semibold">
                        {invoice.invoiceNumber ?? "下書き"}
                      </TextLink>
                    </TableCell>
                    <TableCell truncate>{invoice.customer.name}</TableCell>
                    <TableCell>
                      <DateText iso={invoice.periodStart} businessDate={businessDate} />
                      <span className="text-muted-foreground">〜</span>
                      <DateText iso={invoice.periodEnd} businessDate={businessDate} />
                    </TableCell>
                    <TableCell>
                      <StatusBadge style={INVOICE_STATE[invoice.state]} value={invoice.state} />
                    </TableCell>
                    <TableCell>
                      <DateText iso={invoice.issuedAt} businessDate={businessDate} withTime />
                    </TableCell>
                    <TableCell numeric>{yen(invoice.total)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
          <Pagination pageInfo={data.invoices.pageInfo} />
        </>
      )}
    </section>
  );
}
