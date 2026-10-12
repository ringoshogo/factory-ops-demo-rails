import { BillingTermForm, ClosePeriodForm } from "@/components/billing-forms";
import { DateText } from "@/components/date-text";
import { FilterBar } from "@/components/filter-bar";
import { FilterMenu } from "@/components/filter-menu";
import { ListError } from "@/components/list-error";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { yen } from "@/lib/format";
import { SupplierBillingDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { nodesOf, pageArgs, single, toParams, type SearchParams } from "@/lib/list";
import { isAdmin } from "@/lib/viewer";

/** 締め日の値の見せ方。31 は月末を表す。 */
const closingDayLabel = (day: number) => (day === 31 ? "月末" : `${day}日`);

/** 業務の今日の月の末日 (YYYY-MM-DD)。 */
function endOfMonth(businessDate: string): string {
  const [year, month] = businessDate.split("-").map(Number);
  const last = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return `${businessDate.slice(0, 7)}-${String(last).padStart(2, "0")}`;
}

// 請求の締め。取引先ごとの締め日と、未請求の明細 (検収済で、まだ請求書にまとめていないもの) を並べ、締めると
// 下書きの請求書ができる。締め日の設定と締めは admin に限る (docs/architecture/graphql-schema.md「役割による制限」)
export default async function BillingPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = toParams(await searchParams);
  const customerTenantId = single(params, "customer");
  const [result, admin] = await Promise.all([
    query(SupplierBillingDocument, { ...pageArgs(params), customerTenantId }),
    isAdmin(),
  ]);
  const error = result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.kind === "error" ? result.message : null;
  const data = result.kind === "ok" ? result.data.supplier : null;
  const businessDate = data?.dashboard.businessDate ?? null;

  // 失効の後に結び直した取引先は 1 つにまとめる。締め日は有効な取引関係の相手にだけ設定できる
  const customers = [...new Map((data?.partnerships ?? []).map((p) => [p.buyer.id, p.buyer])).values()];
  const active = new Set((data?.partnerships ?? []).filter((p) => p.status === "ACTIVE").map((p) => p.buyer.id));
  const terms = new Map((data?.billingTerms ?? []).map((t) => [t.customer.id, t.closingDay]));
  const items = data ? nodesOf(data.billableItems) : [];

  return (
    <section className="flex flex-col gap-8">
      <PageHeader
        title="請求の締め"
        description={data ? <>未請求の合計（税抜き） {yen(data.dashboard.unbilledTotal)} 円</> : undefined}
      />

      {error || !data ? (
        <ListError>{error}</ListError>
      ) : (
        <>
          <div>
            <h2 className="mb-3.5 text-base font-semibold">取引先ごとの締め日</h2>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>取引先</TableHead>
                  <TableHead>締め日</TableHead>
                  {admin && <TableHead>締め日を変える（1〜28、月末は 31）</TableHead>}
                </TableRow>
              </TableHeader>
              <TableBody>
                {customers.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={admin ? 3 : 2} className="text-muted-foreground py-8 text-center">
                      取引先がありません
                    </TableCell>
                  </TableRow>
                )}
                {customers.map((c) => {
                  const day = terms.get(c.id) ?? null;
                  return (
                    <TableRow key={c.id} data-testid="billing-term-row">
                      <TableCell truncate>{c.name}</TableCell>
                      <TableCell>{day === null ? "未設定" : closingDayLabel(day)}</TableCell>
                      {admin && (
                        <TableCell>
                          {active.has(c.id) ? (
                            <BillingTermForm customer={c} closingDay={day} />
                          ) : (
                            <span className="text-muted-foreground text-[13px]">取引関係が失効しています</span>
                          )}
                        </TableCell>
                      )}
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>

          {admin && businessDate && (
            <div>
              <h2 className="mb-3.5 text-base font-semibold">締める</h2>
              <ClosePeriodForm customers={customers} defaultDate={endOfMonth(businessDate)} />
            </div>
          )}

          <div className="space-y-4">
            <h2 className="text-base font-semibold">未請求の明細</h2>
            <FilterBar count={data.billableItems.totalCount}>
              <FilterMenu
                label="取引先"
                icon="customer"
                param="customer"
                value={customerTenantId ?? ""}
                options={[{ value: "", label: "すべて" }, ...customers.map((c) => ({ value: c.id, label: c.name }))]}
              />
            </FilterBar>
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>検収日</TableHead>
                    <TableHead>取引先</TableHead>
                    <TableHead>品目</TableHead>
                    <TableHead numeric>数量</TableHead>
                    <TableHead numeric>単価</TableHead>
                    <TableHead numeric>税率</TableHead>
                    <TableHead numeric>金額</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {items.length === 0 && (
                    <TableRow data-testid="empty-row">
                      <TableCell colSpan={7} className="text-muted-foreground py-8 text-center">
                        未請求の明細はありません
                      </TableCell>
                    </TableRow>
                  )}
                  {items.map((item) => (
                    <TableRow key={item.id} data-testid="list-row">
                      <TableCell>
                        <DateText iso={item.inspectedOn} businessDate={businessDate} />
                      </TableCell>
                      <TableCell truncate>{item.customer.name}</TableCell>
                      <TableCell truncate="wide">{item.itemName}</TableCell>
                      <TableCell numeric>{item.quantity}</TableCell>
                      <TableCell numeric>{yen(item.unitPrice)}</TableCell>
                      <TableCell numeric>{item.taxRatePercent}%</TableCell>
                      <TableCell numeric>{yen(item.amount)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
            <Pagination pageInfo={data.billableItems.pageInfo} />
          </div>
        </>
      )}
    </section>
  );
}
