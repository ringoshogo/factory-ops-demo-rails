import type { ReactNode } from "react";
import { TextLink } from "@/components/app-link";
import { ColumnHeads, sortColumns, type Column } from "@/components/columns";
import { DateText } from "@/components/date-text";
import { FilterBar, SearchForm } from "@/components/filter-bar";
import { FilterMenu } from "@/components/filter-menu";
import { LinkTabs } from "@/components/link-tabs";
import { ListError } from "@/components/list-error";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { AlertBadge } from "@/components/status-badge";
import { StockAdjustDialog } from "@/components/stock-adjust-dialog";
import { Table, TableActions, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatNumber } from "@/lib/format";
import { SupplierStockMovementsDocument, SupplierStocksDocument, type StockOrderField } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { nodesOf, single, toParams, type SearchParams } from "@/lib/list";
import { patchHref } from "@/lib/query";
import { STOCK_MOVEMENT_TYPE } from "@/lib/statuses";
import { STOCK_MOVEMENT_TYPES, stockListVariables, stockMovementVariables } from "@/lib/supplier-master-lists";

// 並べ替えの見出しは API の orderBy の field から作る。品目のコードと名前は、API が在庫に写した品目の写しで並べる
const SORT = sortColumns<StockOrderField>(
  {
    ITEM_CODE: "品目コード",
    ITEM_NAME: "品目名",
    ON_HAND: "現在庫",
    ALLOCATED: "引当",
    AVAILABLE: "有効在庫",
    SAFETY_STOCK: "安全在庫",
  },
  {
    ITEM_CODE: { truncate: true },
    ITEM_NAME: { truncate: true },
    ON_HAND: { numeric: true },
    ALLOCATED: { numeric: true },
    AVAILABLE: { numeric: true },
    SAFETY_STOCK: { numeric: true },
  },
);

const COLUMNS: Column<StockOrderField>[] = [
  SORT.ITEM_CODE,
  SORT.ITEM_NAME,
  SORT.ON_HAND,
  SORT.ALLOCATED,
  SORT.AVAILABLE,
  SORT.SAFETY_STOCK,
];

// 在庫と移動履歴。移動履歴は在庫の画面のタブにする
export default async function StocksPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = toParams(await searchParams);
  const tab = single(params, "tab") === "movements" ? "movements" : "stocks";

  return (
    <section className="space-y-5">
      <PageHeader title="在庫" divider={false} />
      <LinkTabs
        label="在庫の表示"
        tabs={[
          { href: "/supplier/stocks", label: "在庫一覧", current: tab === "stocks" },
          { href: "/supplier/stocks?tab=movements", label: "移動履歴", current: tab === "movements" },
        ]}
      />
      {tab === "movements" ? <Movements params={params} /> : <Stocks params={params} />}
    </section>
  );
}

async function Stocks({ params }: { params: URLSearchParams }) {
  const variables = stockListVariables(params);
  const result = await query(SupplierStocksDocument, variables);
  const error = result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.kind === "error" ? result.message : null;
  const stocks = result.kind === "ok" ? result.data.supplier.stocks : null;

  return (
    <div className="space-y-4">
      <FilterBar count={stocks ? stocks.totalCount : null}>
        <SearchForm defaultValue={single(params, "q") ?? ""} placeholder="コード・品目名で検索">
          {/* 送っても並べ替えと安全在庫の絞り込みを保つ。検索を変えると 1 ページ目に戻る (after を送らない) */}
          {variables.orderBy && (
            <>
              <input type="hidden" name="sort" value={variables.orderBy.field.toLowerCase()} />
              <input type="hidden" name="dir" value={variables.orderBy.direction.toLowerCase()} />
            </>
          )}
          {variables.filter?.belowSafetyStock && <input type="hidden" name="below" value="1" />}
        </SearchForm>
        {/* ダッシュボードの「安全在庫を下回る在庫」と同じ条件を API が数えるので、件数がダッシュボードと一致する */}
        <FilterMenu
          label="在庫"
          icon="stock"
          param="below"
          value={variables.filter?.belowSafetyStock ? "1" : ""}
          options={[
            { value: "", label: "すべて" },
            { value: "1", label: "安全在庫を下回るものだけ" },
          ]}
        />
      </FilterBar>

      {error || !stocks ? (
        <ListError>{error}</ListError>
      ) : (
        <>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <ColumnHeads columns={COLUMNS} state={variables.orderBy} />
                  <TableHead>操作</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {nodesOf(stocks).length === 0 && (
                  <TableRow data-testid="empty-row">
                    <TableCell colSpan={COLUMNS.length + 1} className="text-muted-foreground py-8 text-center">
                      該当する在庫がありません
                    </TableCell>
                  </TableRow>
                )}
                {nodesOf(stocks).map((s) => {
                  const content: Record<string, ReactNode> = {
                    ITEM_CODE: s.item.code,
                    ITEM_NAME: s.item.name,
                    ON_HAND: <span data-testid="on-hand">{formatNumber(s.onHand)}</span>,
                    ALLOCATED: <span data-testid="allocated">{formatNumber(s.allocated)}</span>,
                    // 有効在庫が安全在庫を下回る在庫は、色だけでなく札の文字でも示す
                    AVAILABLE: (
                      <span className="inline-flex items-center justify-end gap-2">
                        {s.belowSafetyStock && <AlertBadge />}
                        <span data-testid="available" className={s.belowSafetyStock ? "font-semibold" : ""}>
                          {formatNumber(s.available)}
                        </span>
                      </span>
                    ),
                    SAFETY_STOCK: <span className="text-muted-foreground">{formatNumber(s.safetyStock)}</span>,
                  };
                  return (
                    <TableRow key={s.item.id} data-testid="list-row">
                      {COLUMNS.map((c) => (
                        <TableCell key={c.key} numeric={c.numeric} truncate={c.truncate} sortable={Boolean(c.sort)}>
                          {content[c.key]}
                        </TableCell>
                      ))}
                      <TableCell>
                        <TableActions>
                          <StockAdjustDialog
                            target={{
                              itemId: s.item.id,
                              code: s.item.code,
                              name: s.item.name,
                              onHand: s.onHand,
                              allocated: s.allocated,
                              available: s.available,
                            }}
                          />
                          <TextLink href={`/supplier/stocks?tab=movements&item=${s.item.id}`} className="text-sm">
                            履歴
                          </TextLink>
                        </TableActions>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
          <Pagination pageInfo={stocks.pageInfo} />
        </>
      )}
    </div>
  );
}

async function Movements({ params }: { params: URLSearchParams }) {
  const variables = stockMovementVariables(params);
  const result = await query(SupplierStockMovementsDocument, variables);
  const error = result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.kind === "error" ? result.message : null;
  const data = result.kind === "ok" ? result.data.supplier : null;
  const movements = data?.stockMovements ?? null;
  const businessDate = data?.dashboard.businessDate ?? null;
  const rows = movements ? nodesOf(movements) : [];
  // 品目で絞っているときは、その品目の名前を行から読む。行が無ければ ID のまま出す
  const itemLabel = variables.itemId ? (rows[0] ? `${rows[0].item.code} ${rows[0].item.name}` : variables.itemId) : null;

  return (
    <div className="space-y-4">
      <FilterBar count={movements ? movements.totalCount : null}>
        <FilterMenu
          label="種類"
          icon="movement"
          param="type"
          value={variables.filter?.types[0] ?? ""}
          options={[
            { value: "", label: "すべて" },
            ...STOCK_MOVEMENT_TYPES.map((t) => ({ value: t, label: STOCK_MOVEMENT_TYPE[t] })),
          ]}
        />
        {itemLabel && (
          <span data-testid="item-filter" className="text-muted-foreground inline-flex items-center gap-2 text-[13px]">
            品目 {itemLabel}
            <TextLink href={patchHref("/supplier/stocks", params, { item: null, after: null })}>解除</TextLink>
          </span>
        )}
      </FilterBar>

      {error || !movements ? (
        <ListError>{error}</ListError>
      ) : (
        <>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>日時</TableHead>
                  <TableHead>品目</TableHead>
                  <TableHead>種類</TableHead>
                  <TableHead numeric>数量</TableHead>
                  <TableHead>理由</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.length === 0 && (
                  <TableRow data-testid="empty-row">
                    <TableCell colSpan={5} className="text-muted-foreground py-8 text-center">
                      該当する履歴がありません
                    </TableCell>
                  </TableRow>
                )}
                {rows.map((m) => (
                  <TableRow key={m.id} data-testid="movement-row">
                    <TableCell className="whitespace-nowrap">
                      <DateText iso={m.createdAt} businessDate={businessDate} withTime />
                    </TableCell>
                    <TableCell truncate>
                      {m.item.code} {m.item.name}
                    </TableCell>
                    <TableCell data-testid="movement-type">{STOCK_MOVEMENT_TYPE[m.type]}</TableCell>
                    <TableCell numeric>{formatNumber(m.quantity)}</TableCell>
                    <TableCell truncate className="text-muted-foreground">
                      {m.reason ?? "—"}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
          <Pagination pageInfo={movements.pageInfo} />
        </>
      )}
    </div>
  );
}
