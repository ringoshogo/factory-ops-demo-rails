import type { ReactNode } from "react";
import { TextLink } from "@/components/app-link";
import { ColumnHeads, sortColumns, sortCell, type Column } from "@/components/columns";
import { FilterBar, SearchForm } from "@/components/filter-bar";
import { ItemDialog, PublishButton } from "@/components/item-forms";
import { ListError } from "@/components/list-error";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { StatusBadge } from "@/components/status-badge";
import { Table, TableActions, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatNumber, yen } from "@/lib/format";
import { SupplierItemsDocument, type ItemOrderField } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { nodesOf, parseSort, single, sortParams, toParams, type SearchParams } from "@/lib/list";
import { ITEM_SORT_FIELDS, itemListVariables } from "@/lib/supplier-master-lists";

// 並べ替えの見出しは API の orderBy の field から作る。単価・税率・在庫は API で並べられないので、ただの見出しにする
const SORT = sortColumns<ItemOrderField>({ CODE: "品目コード", NAME: "品目名" }, { CODE: { truncate: true }, NAME: { truncate: true } });

const COLUMNS: Column<ItemOrderField>[] = [
  SORT.CODE,
  SORT.NAME,
  { key: "unit", label: "単位" },
  { key: "unitPrice", label: "単価", numeric: true },
  { key: "tax", label: "税率", numeric: true },
  { key: "available", label: "有効在庫", numeric: true },
  { key: "published", label: "カタログ" },
];

const PUBLISHED = { label: "公開", tone: "shipped" } as const;
const UNPUBLISHED = { label: "非公開", tone: "received" } as const;

// 品目の一覧。1 ページずつ読み、並べ替えと検索はサーバーが行う。検索の語と並べ替えは URL に載せる
export default async function ItemsPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = toParams(await searchParams);
  const sort = parseSort(params, ITEM_SORT_FIELDS);
  const kept = sortParams(sort);
  const variables = itemListVariables(params);
  const result = await query(SupplierItemsDocument, variables);
  const error = result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.kind === "error" ? result.message : null;
  const items = result.kind === "ok" ? result.data.supplier.items : null;

  return (
    <section className="space-y-4">
      <PageHeader title="品目">
        <ItemDialog />
      </PageHeader>

      <FilterBar count={items ? items.totalCount : null}>
        <SearchForm defaultValue={single(params, "q") ?? ""} placeholder="コード・品目名で検索">
          {/* 送っても並べ替えを保つ。検索を変えると 1 ページ目に戻る (after を送らない) */}
          {kept.sort && kept.dir && (
            <>
              <input type="hidden" name="sort" value={kept.sort} />
              <input type="hidden" name="dir" value={kept.dir} />
            </>
          )}
        </SearchForm>
      </FilterBar>

      {error || !items ? (
        <ListError>{error}</ListError>
      ) : (
        <>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <ColumnHeads columns={COLUMNS} state={sort} />
                  <TableHead>操作</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {nodesOf(items).length === 0 && (
                  <TableRow data-testid="empty-row">
                    <TableCell colSpan={COLUMNS.length + 1} className="text-muted-foreground py-8 text-center">
                      該当する品目がありません
                    </TableCell>
                  </TableRow>
                )}
                {nodesOf(items).map((item) => {
                  const content: Record<string, ReactNode> = {
                    CODE: (
                      <TextLink href={`/supplier/items/${item.id}`} className="rounded-sm font-semibold">
                        {item.code}
                      </TextLink>
                    ),
                    NAME: item.name,
                    unit: item.unit,
                    unitPrice: yen(item.unitPrice),
                    tax: `${item.taxRatePercent}%`,
                    available: item.stock ? formatNumber(item.stock.available) : "—",
                    published: <StatusBadge style={item.published ? PUBLISHED : UNPUBLISHED} />,
                  };
                  return (
                    <TableRow key={item.id} data-testid="list-row">
                      {COLUMNS.map((c) => (
                        <TableCell key={c.key} numeric={c.numeric} truncate={c.truncate} {...sortCell(c, sort)}>
                          {content[c.key]}
                        </TableCell>
                      ))}
                      <TableCell>
                        {/* 1280px 未満は 2 つのボタンを縦に積み、操作の列を狭めて 1024px で表をパネルに収める */}
                        <TableActions className="flex-col items-start xl:flex-row xl:items-center">
                          <ItemDialog
                            item={{
                              code: item.code,
                              name: item.name,
                              unit: item.unit,
                              unitPrice: item.unitPrice,
                              taxRatePercent: item.taxRatePercent,
                            }}
                          />
                          <PublishButton itemId={item.id} published={item.published} />
                        </TableActions>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
          <Pagination pageInfo={items.pageInfo} />
        </>
      )}
    </section>
  );
}
