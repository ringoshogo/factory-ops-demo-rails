import { TextLink } from "@/components/app-link";
import { FilterBar } from "@/components/filter-bar";
import { FilterMenu } from "@/components/filter-menu";
import { ListError } from "@/components/list-error";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { PartMappingForm, type AwaitingLine } from "@/components/part-mapping-form";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { SupplierPartMappingsDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { nodesOf, toParams, type SearchParams } from "@/lib/list";
import { partMappingVariables } from "@/lib/supplier-master-lists";

// 品番の対応表。発注側は自社品番で発注するので、受注側は得意先品番と自社の品目の対応を取引先ごとに持つ。
// 対応の無い明細を持つ受注は品番照合待ちになり、対応を登録すると受注確定へ進む
export default async function PartMappingsPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = toParams(await searchParams);
  const variables = partMappingVariables(params);
  const result = await query(SupplierPartMappingsDocument, variables);
  if (result.kind !== "ok") {
    return (
      <section className="space-y-4">
        <PageHeader title="品番の対応表" />
        <ListError>{result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.message}</ListError>
      </section>
    );
  }
  const data = result.data.supplier;
  // 失効の後に結び直した取引先は関係が 2 つあるので、取引先の選択肢を 1 つにまとめる。登録は有効な関係の相手に限る
  const customers = [...new Map(data.partnerships.map((p) => [p.buyer.id, p])).values()];
  const active = customers.filter((p) => data.partnerships.some((q) => q.buyer.id === p.buyer.id && q.status === "ACTIVE"));
  const awaiting: AwaitingLine[] = nodesOf(data.awaiting).flatMap((order) =>
    order.lines
      .filter((line) => line.item === null)
      .map((line) => ({
        key: line.id,
        customerTenantId: order.customer.id,
        customerName: order.customer.name,
        orderNo: order.orderNo,
        customerPartNumber: line.customerPartNumber,
        quantity: line.quantity,
      })),
  );
  const mappings = nodesOf(data.partMappings);

  return (
    <section className="flex flex-col gap-8">
      <PageHeader title="品番の対応表" />

      <PartMappingForm
        customers={active.map((p) => ({ id: p.buyer.id, label: p.buyer.name }))}
        items={nodesOf(data.candidates).map((i) => ({ id: i.id, label: `${i.code} ${i.name}` }))}
        awaiting={awaiting}
      />
      {data.awaiting.totalCount > awaiting.length && (
        <p className="text-muted-foreground -mt-6 text-[13px]">
          照合待ちの受注 {data.awaiting.totalCount} 件のうち、受注番号の小さい 10 件の明細を出しています。
          <TextLink href="/supplier/sales-orders?status=AWAITING_PART_MATCH" className="ml-2">
            受注一覧で見る
          </TextLink>
        </p>
      )}

      <div className="space-y-4">
        <h2 className="text-base font-semibold">登録済みの対応</h2>
        <FilterBar count={data.partMappings.totalCount}>
          <FilterMenu
            label="取引先"
            icon="customer"
            param="customer"
            value={variables.customerTenantId ?? ""}
            options={[{ value: "", label: "すべて" }, ...customers.map((p) => ({ value: p.buyer.id, label: p.buyer.name }))]}
          />
        </FilterBar>
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>取引先</TableHead>
                <TableHead>得意先品番</TableHead>
                <TableHead>品目コード</TableHead>
                <TableHead>品目名</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {mappings.length === 0 && (
                <TableRow data-testid="empty-row">
                  <TableCell colSpan={4} className="text-muted-foreground py-8 text-center">
                    該当する対応がありません
                  </TableCell>
                </TableRow>
              )}
              {mappings.map((m) => (
                <TableRow key={m.id} data-testid="list-row">
                  <TableCell truncate>{m.customer.name}</TableCell>
                  <TableCell>{m.customerPartNumber}</TableCell>
                  <TableCell>
                    <TextLink href={`/supplier/items/${m.item.id}`}>{m.item.code}</TextLink>
                  </TableCell>
                  <TableCell truncate>{m.item.name}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
        <Pagination pageInfo={data.partMappings.pageInfo} />
      </div>
    </section>
  );
}
