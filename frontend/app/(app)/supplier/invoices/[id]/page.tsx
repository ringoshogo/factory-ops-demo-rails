import { notFound } from "next/navigation";
import { TextLink } from "@/components/app-link";
import { DateText } from "@/components/date-text";
import { ErrorNotice } from "@/components/error-notice";
import { InvoiceActions } from "@/components/invoice-actions";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { StatusBadge } from "@/components/status-badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { yen } from "@/lib/format";
import { SupplierInvoiceDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { nodesOf, pageArgs, toParams, type SearchParams } from "@/lib/list";
import { INVOICE_STATE } from "@/lib/statuses";
import { isAdmin } from "@/lib/viewer";

// 請求書の詳細。明細は請求書を 1 件に決めてから 1 ページずつ引く。単価の説明は、受注明細が単価を引いた日の単価を、
// いま分かっている値と、発行の時点で信じていた値で並べ、後から訂正された単価を見分けられるようにする
// (docs/adr/006-販売単価を有効期間と記録期間の2軸で持つ.md)
export default async function InvoicePage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const { id } = await params;
  const search = toParams(await searchParams);
  const [result, admin] = await Promise.all([query(SupplierInvoiceDocument, { id, ...pageArgs(search) }), isAdmin()]);
  if (result.kind !== "ok") {
    return (
      <section className="space-y-5">
        <PageHeader title="請求書" />
        <ErrorNotice data-testid="detail-error">
          {result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.message}
        </ErrorNotice>
      </section>
    );
  }
  const invoice = result.data.supplier.invoice;
  if (!invoice) notFound();
  const businessDate = result.data.supplier.dashboard.businessDate;
  const items = nodesOf(invoice.items);
  const draft = invoice.state === "DRAFT";

  return (
    <section className="flex flex-col gap-8">
      <PageHeader
        title={invoice.invoiceNumber ? `請求書 ${invoice.invoiceNumber}` : "請求書（下書き）"}
        description={<TextLink href="/supplier/invoices">請求書の一覧へ</TextLink>}
      >
        {draft && admin && <InvoiceActions invoiceId={invoice.id} />}
      </PageHeader>

      <dl className="grid max-w-2xl grid-cols-[8rem_1fr] gap-x-6 gap-y-3 text-sm">
        <dt className="text-muted-foreground">取引先</dt>
        <dd>{invoice.customer.name}</dd>
        <dt className="text-muted-foreground">状況</dt>
        <dd>
          <StatusBadge style={INVOICE_STATE[invoice.state]} value={invoice.state} />
        </dd>
        <dt className="text-muted-foreground">請求期間</dt>
        <dd>
          <DateText iso={invoice.periodStart} businessDate={businessDate} />〜
          <DateText iso={invoice.periodEnd} businessDate={businessDate} />
        </dd>
        <dt className="text-muted-foreground">発行日時</dt>
        <dd>
          <DateText iso={invoice.issuedAt} businessDate={businessDate} withTime />
        </dd>
      </dl>

      <div className="space-y-3">
        <h2 className="text-base font-semibold">明細（{invoice.items.totalCount} 件）</h2>
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>検収日</TableHead>
                <TableHead>品目</TableHead>
                <TableHead numeric>数量</TableHead>
                <TableHead numeric>単価</TableHead>
                <TableHead>単価の説明</TableHead>
                <TableHead numeric>税率</TableHead>
                <TableHead numeric>金額</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((item) => {
                const p = item.priceExplanation;
                const corrected = p.unitPriceNow !== p.orderedUnitPrice;
                return (
                  <TableRow key={item.id} data-testid="invoice-item-row">
                    <TableCell>
                      <DateText iso={item.inspectedOn} businessDate={businessDate} />
                    </TableCell>
                    <TableCell truncate="wide">{item.itemName}</TableCell>
                    <TableCell numeric>{item.quantity}</TableCell>
                    <TableCell numeric>{yen(item.unitPrice)}</TableCell>
                    <TableCell className="text-muted-foreground text-[13px]">
                      <DateText iso={p.pricedOn} businessDate={businessDate} /> の単価
                      {p.unitPriceAsOfIssue !== null && <>・発行時 {yen(p.unitPriceAsOfIssue)}</>}
                      {corrected && <span className="text-caution">・いまの値 {yen(p.unitPriceNow)}</span>}
                    </TableCell>
                    <TableCell numeric>{item.taxRatePercent}%</TableCell>
                    <TableCell numeric>{yen(item.amount)}</TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </div>
        <Pagination pageInfo={invoice.items.pageInfo} />
      </div>

      <dl className="ml-auto grid w-full max-w-sm grid-cols-[1fr_auto] gap-x-6 gap-y-2 text-sm tabular-nums">
        <dt className="text-muted-foreground">小計（税抜き）</dt>
        <dd className="text-right">{yen(invoice.subtotal)}</dd>
        {invoice.taxSummaries.map((t) => (
          <div key={t.taxRatePercent} className="contents">
            <dt className="text-muted-foreground">
              消費税 {t.taxRatePercent}%（対象 {yen(t.taxableAmount)}）
            </dt>
            <dd className="text-right">{yen(t.taxAmount)}</dd>
          </div>
        ))}
        <dt className="font-semibold">合計</dt>
        <dd data-testid="invoice-total" className="text-right font-semibold">
          {yen(invoice.total)}
        </dd>
      </dl>
    </section>
  );
}
