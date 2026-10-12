import { TextLink } from "@/components/app-link";
import { DateText } from "@/components/date-text";
import { FilterBar } from "@/components/filter-bar";
import { ListError } from "@/components/list-error";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { yen } from "@/lib/format";
import { BuyerReceivedInvoicesDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { nodesOf, pageArgs, toParams, type SearchParams } from "@/lib/list";

// 受領請求書の一覧。受注側が確定した請求書が、イベントで発注側に届いたもの。並べ替えと絞り込みは API に無いので、
// API の並びのまま 1 ページずつ読む
export default async function ReceivedInvoicesPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = toParams(await searchParams);
  const result = await query(BuyerReceivedInvoicesDocument, pageArgs(params));
  const error = result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.kind === "error" ? result.message : null;
  const data = result.kind === "ok" ? result.data : null;
  const businessDate = data?.supplier.dashboard.businessDate ?? null;
  const rows = data ? nodesOf(data.buyer.receivedInvoices) : [];

  return (
    <section className="space-y-5">
      <PageHeader title="受領請求書" />
      <FilterBar count={data ? data.buyer.receivedInvoices.totalCount : null}>{null}</FilterBar>
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
                  <TableHead>発行日</TableHead>
                  <TableHead>請求期間</TableHead>
                  <TableHead numeric>請求金額（税込）</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.length === 0 && (
                  <TableRow data-testid="empty-row">
                    <TableCell colSpan={5} className="text-muted-foreground py-8 text-center">
                      受け取った請求書はありません
                    </TableCell>
                  </TableRow>
                )}
                {rows.map((invoice) => (
                  <TableRow key={invoice.id} data-testid="list-row">
                    <TableCell>
                      <TextLink href={`/buyer/received-invoices/${invoice.id}`} className="font-semibold">
                        {invoice.invoiceNumber}
                      </TextLink>
                    </TableCell>
                    <TableCell truncate>{invoice.supplier.name}</TableCell>
                    <TableCell>
                      <DateText iso={invoice.issuedOn} businessDate={businessDate} />
                    </TableCell>
                    <TableCell>
                      <DateText iso={invoice.periodStart} businessDate={businessDate} />〜
                      <DateText iso={invoice.periodEnd} businessDate={businessDate} />
                    </TableCell>
                    <TableCell numeric>{yen(invoice.total)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
          <Pagination pageInfo={data.buyer.receivedInvoices.pageInfo} />
        </>
      )}
    </section>
  );
}
