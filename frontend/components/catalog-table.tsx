import { ListError } from "@/components/list-error";
import { Pagination } from "@/components/pagination";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { yen } from "@/lib/format";
import type { BuyerSupplierCatalogQuery } from "@/lib/graphql/generated";
import { nodesOf } from "@/lib/list";

type Partnership = BuyerSupplierCatalogQuery["buyer"]["supplier"];

/**
 * 取引先が公開した品目 (経路 1 のカタログ)。取引関係が無いか失効していれば相手そのものが返らず、カタログの付与が
 * 無ければカタログが空で返る。どちらも「見られる品目が無い」と出し、どちらなのかを画面で推し量って言い分けない。
 * 品番は受注側のコードで、発注には自社品番を使う。
 */
export function CatalogTable({ partnership }: { partnership: Partnership }) {
  if (!partnership) {
    return <ListError>この取引先のカタログは見られません。取引関係とカタログの付与を確かめてください。</ListError>;
  }
  const rows = nodesOf(partnership.catalog);
  return (
    <div className="space-y-3">
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>品目コード</TableHead>
              <TableHead>品目名</TableHead>
              <TableHead>単位</TableHead>
              <TableHead numeric>単価</TableHead>
              <TableHead numeric>税率</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 && (
              <TableRow data-testid="empty-row">
                <TableCell colSpan={5} className="text-muted-foreground py-8 text-center">
                  見られる品目がありません
                </TableCell>
              </TableRow>
            )}
            {rows.map((item) => (
              <TableRow key={item.code} data-testid="catalog-row">
                <TableCell className="text-muted-foreground">{item.code}</TableCell>
                <TableCell truncate>{item.name}</TableCell>
                <TableCell>{item.unit}</TableCell>
                <TableCell numeric>{yen(item.unitPrice)}</TableCell>
                <TableCell numeric>{item.taxRatePercent}%</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <Pagination pageInfo={partnership.catalog.pageInfo} />
    </div>
  );
}
