import { TextLink } from "@/components/app-link";
import { CatalogTable } from "@/components/catalog-table";
import { ListError } from "@/components/list-error";
import { PageHeader } from "@/components/page-header";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { BuyerSupplierCatalogDocument, BuyerSuppliersDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { pageArgs, single, toParams, type SearchParams } from "@/lib/list";
import { PERMISSION_LABEL, PERMISSION_ORDER } from "@/lib/statuses";

// 取引先とカタログ。取引先の一覧にカタログを入れ子にせず (取引先ごとにページングの問い合わせが出る)、
// 1 社を選んでから、その相手のカタログを 1 ページずつ読む
export default async function SuppliersPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = toParams(await searchParams);
  const selected = single(params, "supplier");
  const [list, catalog] = await Promise.all([
    query(BuyerSuppliersDocument),
    selected ? query(BuyerSupplierCatalogDocument, { supplierTenantId: selected, ...pageArgs(params) }) : null,
  ]);

  if (list.kind !== "ok") {
    return (
      <section className="space-y-5">
        <PageHeader title="取引先とカタログ" />
        <ListError>{list.kind === "unreachable" ? UNREACHABLE_MESSAGE : list.message}</ListError>
      </section>
    );
  }
  const suppliers = list.data.buyer.suppliers;

  return (
    <section className="space-y-8">
      <PageHeader title="取引先とカタログ" />

      {suppliers.length === 0 ? (
        <p data-testid="empty-suppliers" className="text-muted-foreground py-8 text-center text-sm">
          取引関係のある受注側がありません
        </p>
      ) : (
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>取引先</TableHead>
                <TableHead>権限の付与</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {suppliers.map(({ supplier, permissions }) => (
                <TableRow
                  key={supplier.id}
                  data-testid="supplier-row"
                  aria-current={supplier.id === selected ? "true" : undefined}
                >
                  <TableCell truncate="wide">
                    <TextLink href={`/buyer/suppliers?supplier=${supplier.id}`} className="font-semibold">
                      {supplier.name}
                    </TextLink>
                  </TableCell>
                  <TableCell>
                    <span className="flex flex-wrap gap-1.5">
                      {PERMISSION_ORDER.filter((p) => permissions.includes(p)).map((p) => (
                        <span
                          key={p}
                          data-testid="permission"
                          className="bg-neutral-chip text-foreground-2 rounded-badge px-1.5 py-px text-xs font-medium"
                        >
                          {PERMISSION_LABEL[p]}
                        </span>
                      ))}
                      {permissions.length === 0 && <span className="text-muted-foreground text-[13px]">付与なし</span>}
                    </span>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      {selected && (
        <div className="space-y-3">
          <h2 className="text-base font-semibold">
            {catalog?.kind === "ok" && catalog.data.buyer.supplier
              ? `${catalog.data.buyer.supplier.supplier.name} のカタログ`
              : "カタログ"}
          </h2>
          {catalog === null || catalog.kind !== "ok" ? (
            <ListError>{catalog?.kind === "error" ? catalog.message : UNREACHABLE_MESSAGE}</ListError>
          ) : (
            <CatalogTable partnership={catalog.data.buyer.supplier} />
          )}
        </div>
      )}
    </section>
  );
}
