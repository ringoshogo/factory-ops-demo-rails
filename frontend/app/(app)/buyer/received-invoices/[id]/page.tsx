import { notFound } from "next/navigation";
import { DateText } from "@/components/date-text";
import { ErrorNotice } from "@/components/error-notice";
import { PageHeader } from "@/components/page-header";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { yen } from "@/lib/format";
import { BuyerReceivedInvoiceDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";

// 受領請求書の詳細。金額は受注側が確定した値をそのまま出し、画面で足し直さない。税は請求書の税率ごとに 1 回だけ
// 切り捨てているので、明細ごとの税を画面で足すと合わない
export default async function ReceivedInvoicePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const result = await query(BuyerReceivedInvoiceDocument, { id });
  if (result.kind !== "ok") {
    return (
      <ErrorNotice data-testid="detail-error">
        {result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.message}
      </ErrorNotice>
    );
  }
  const invoice = result.data.buyer.receivedInvoice;
  if (!invoice) notFound();
  const businessDate = result.data.supplier.dashboard.businessDate;

  return (
    <section className="space-y-6">
      <PageHeader
        title={
          <>
            受領請求書 <span data-testid="invoice-number">{invoice.invoiceNumber}</span>
          </>
        }
      />
      <dl className="rounded-card grid gap-3 border p-4 text-sm sm:grid-cols-3">
        <div>
          <dt className="text-muted-foreground">取引先</dt>
          <dd>{invoice.supplier.name}</dd>
        </div>
        <div>
          <dt className="text-muted-foreground">発行日</dt>
          <dd>
            <DateText iso={invoice.issuedOn} businessDate={businessDate} />
          </dd>
        </div>
        <div>
          <dt className="text-muted-foreground">請求期間</dt>
          <dd>
            <DateText iso={invoice.periodStart} businessDate={businessDate} />〜
            <DateText iso={invoice.periodEnd} businessDate={businessDate} />
          </dd>
        </div>
      </dl>

      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>自社品番</TableHead>
              <TableHead>品目名</TableHead>
              <TableHead numeric>数量</TableHead>
              <TableHead numeric>単価</TableHead>
              <TableHead numeric>税率</TableHead>
              <TableHead numeric>金額（税抜）</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {invoice.lines.map((line, i) => (
              <TableRow key={`${line.purchaseOrderLine.id}-${i}`} data-testid="invoice-line">
                <TableCell>{line.purchaseOrderLine.partNumber}</TableCell>
                <TableCell truncate>{line.itemName}</TableCell>
                <TableCell numeric>{line.quantity}</TableCell>
                <TableCell numeric>{yen(line.unitPrice)}</TableCell>
                <TableCell numeric>{line.taxRatePercent}%</TableCell>
                <TableCell numeric>{yen(line.amount)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>

      <dl className="ml-auto grid w-full max-w-xs grid-cols-2 gap-y-1.5 text-sm tabular-nums">
        <dt className="text-muted-foreground">小計</dt>
        <dd data-testid="invoice-subtotal" className="text-right">{yen(invoice.subtotal)} 円</dd>
        <dt className="text-muted-foreground">消費税</dt>
        <dd data-testid="invoice-tax" className="text-right">{yen(invoice.taxTotal)} 円</dd>
        <dt className="font-semibold">合計</dt>
        <dd data-testid="invoice-total" className="text-right font-semibold">{yen(invoice.total)} 円</dd>
      </dl>
    </section>
  );
}
