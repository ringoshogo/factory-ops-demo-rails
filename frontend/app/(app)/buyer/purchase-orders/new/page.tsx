import { CatalogTable } from "@/components/catalog-table";
import { ErrorNotice } from "@/components/error-notice";
import { PageHeader } from "@/components/page-header";
import { PurchaseOrderForm } from "@/components/purchase-order-form";
import { BuyerOrderFormDocument, BuyerSupplierCatalogDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { pageArgs, single, toParams, type SearchParams } from "@/lib/list";

// 発注の登録。取引先は発注の付与がある相手から選び、選んだ相手のカタログを参照に並べる (取引先とカタログの画面と
// 同じ問い合わせ)。品番は自社品番で入れる
export default async function NewPurchaseOrderPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = toParams(await searchParams);
  const selected = single(params, "supplier") ?? "";
  const [form, catalog] = await Promise.all([
    query(BuyerOrderFormDocument),
    selected ? query(BuyerSupplierCatalogDocument, { supplierTenantId: selected, ...pageArgs(params) }) : null,
  ]);

  if (form.kind !== "ok") {
    return (
      <section className="space-y-5">
        <PageHeader title="発注の登録" />
        <ErrorNotice data-testid="list-error">{form.kind === "unreachable" ? UNREACHABLE_MESSAGE : form.message}</ErrorNotice>
      </section>
    );
  }
  const suppliers = form.data.buyer.suppliers
    .filter((s) => s.permissions.includes("PLACE_ORDERS"))
    .map((s) => s.supplier);

  return (
    <section className="space-y-5">
      <PageHeader title="発注の登録" />
      <div className="grid gap-8 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
        <PurchaseOrderForm suppliers={suppliers} selected={selected} businessDate={form.data.supplier.dashboard.businessDate} />
        <div className="min-w-0 space-y-3">
          <h2 className="text-base font-semibold">カタログ</h2>
          {!selected ? (
            <p className="text-muted-foreground text-sm">取引先を選ぶと、その相手が公開した品目が並びます。</p>
          ) : catalog === null || catalog.kind !== "ok" ? (
            <ErrorNotice data-testid="list-error">
              {catalog?.kind === "error" ? catalog.message : UNREACHABLE_MESSAGE}
            </ErrorNotice>
          ) : (
            <CatalogTable partnership={catalog.data.buyer.supplier} />
          )}
        </div>
      </div>
    </section>
  );
}
