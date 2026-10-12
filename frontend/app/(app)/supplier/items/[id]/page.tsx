import { notFound } from "next/navigation";
import { TextLink } from "@/components/app-link";
import { DateText } from "@/components/date-text";
import { CorrectPriceDialog, SchedulePriceDialog } from "@/components/item-price-forms";
import { ListError } from "@/components/list-error";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { PageHeader } from "@/components/page-header";
import { AlertBadge, StatusBadge } from "@/components/status-badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatNumber, yen } from "@/lib/format";
import { SupplierItemDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { single, toParams, type SearchParams } from "@/lib/list";
import { isAdmin } from "@/lib/viewer";

/** URL の `asOf` (YYYY-MM-DD) を、その日の終わり (日本時間) の時点にする。形の違う値は「いま」にする。 */
function asOfOf(params: URLSearchParams): { date: string | null; at: string | null } {
  const date = single(params, "asOf");
  if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return { date: null, at: null };
  return { date, at: `${date}T23:59:59+09:00` };
}

// 品目の単価の履歴と改定。単価は有効期間 (いつの取引に効くか) と記録期間 (いつそう信じていたか) の 2 つの軸で持ち、
// 行を書き換えない (docs/adr/006)。記録の時点を URL の asOf で選ぶと、その時点で信じていた履歴を読む
export default async function ItemPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const { id } = await params;
  const asOf = asOfOf(toParams(await searchParams));
  const [result, admin] = await Promise.all([query(SupplierItemDocument, { id, asOf: asOf.at }), isAdmin()]);
  if (result.kind !== "ok") {
    return <ListError>{result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.message}</ListError>;
  }
  const item = result.data.supplier.item;
  if (!item) notFound();
  const businessDate = result.data.supplier.dashboard.businessDate;
  // 記録期間が開いている行 (いま正しいと信じている行) だけを訂正できる
  const current = item.prices.filter((p) => p.recordedTo === null);

  return (
    <section className="flex flex-col gap-8">
      <PageHeader title={`${item.code} ${item.name}`} description={<TextLink href="/supplier/items">品目の一覧へ戻る</TextLink>}>
        {admin && <SchedulePriceDialog itemId={item.id} businessDate={businessDate} />}
      </PageHeader>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-3 text-sm sm:grid-cols-4">
        <Fact label="今日の単価" testId="unit-price">{yen(item.unitPrice)} 円</Fact>
        <Fact label="単位">{item.unit}</Fact>
        <Fact label="税率">{item.taxRatePercent}%</Fact>
        <Fact label="カタログ">
          <StatusBadge style={item.published ? { label: "公開", tone: "shipped" } : { label: "非公開", tone: "received" }} />
        </Fact>
        {item.stock && (
          <>
            <Fact label="現在庫">{formatNumber(item.stock.onHand)}</Fact>
            <Fact label="引当">{formatNumber(item.stock.allocated)}</Fact>
            <Fact label="有効在庫">
              <span className="inline-flex items-center gap-2">
                {formatNumber(item.stock.available)}
                {item.stock.belowSafetyStock && <AlertBadge />}
              </span>
            </Fact>
            <Fact label="安全在庫">{formatNumber(item.stock.safetyStock)}</Fact>
          </>
        )}
      </dl>

      <div className="space-y-3">
        <h2 className="flex flex-wrap items-baseline gap-x-3 text-base font-semibold">
          単価の履歴
          <span className="text-muted-foreground text-[13px] font-normal">
            {asOf.date ? `${asOf.date} の終わりの時点の記録` : "いまの記録"}
          </span>
        </h2>
        <form method="get" className="flex flex-wrap items-center gap-2 text-sm">
          <label htmlFor="as-of" className="text-muted-foreground">
            記録の時点
          </label>
          <Input id="as-of" name="asOf" type="date" defaultValue={asOf.date ?? ""} className="w-auto" />
          <Button type="submit" variant="outline">
            読み直す
          </Button>
          {asOf.date && (
            <TextLink href={`/supplier/items/${item.id}`} className="ml-2">
              いまに戻す
            </TextLink>
          )}
        </form>
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>有効期間（終わりの日を含まない）</TableHead>
                <TableHead numeric>単価</TableHead>
                <TableHead>記録期間</TableHead>
                <TableHead>理由</TableHead>
                {admin && <TableHead>操作</TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {item.prices.map((p) => (
                <TableRow key={p.id} data-testid="price-row">
                  <TableCell>
                    <Period from={p.validFrom} to={p.validTo} businessDate={businessDate} />
                  </TableCell>
                  <TableCell numeric>{yen(p.unitPrice)}</TableCell>
                  <TableCell>
                    <DateText iso={p.recordedFrom} businessDate={businessDate} withTime /> 〜{" "}
                    {p.recordedTo ? <DateText iso={p.recordedTo} businessDate={businessDate} withTime /> : "いま"}
                  </TableCell>
                  <TableCell truncate className="text-muted-foreground">
                    {p.reason ?? "—"}
                  </TableCell>
                  {admin && (
                    <TableCell>
                      {!asOf.date && current.includes(p) && (
                        <CorrectPriceDialog itemId={item.id} itemPriceId={p.id} current={p.unitPrice} />
                      )}
                    </TableCell>
                  )}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      </div>
    </section>
  );
}

function Fact({ label, testId, children }: { label: string; testId?: string; children: React.ReactNode }) {
  return (
    <div>
      <dt className="text-muted-foreground text-[13px]">{label}</dt>
      <dd data-testid={testId} className="mt-0.5 font-medium tabular-nums">
        {children}
      </dd>
    </div>
  );
}

/** 有効期間。始まりは含み終わりは含まない。空は上限なし。 */
function Period({ from, to, businessDate }: { from: string | null; to: string | null; businessDate: string }) {
  return (
    <span className="tabular-nums">
      {from ? <DateText iso={from} businessDate={businessDate} /> : "はじめ"} 〜{" "}
      {to ? <DateText iso={to} businessDate={businessDate} /> : "以降ずっと"}
    </span>
  );
}
