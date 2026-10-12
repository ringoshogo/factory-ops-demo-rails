import { TextLink } from "@/components/app-link";
import { DateText } from "@/components/date-text";
import { FilterBar } from "@/components/filter-bar";
import { ImportUpload } from "@/components/import-upload";
import { ListError } from "@/components/list-error";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { StatusBadge } from "@/components/status-badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { SupplierImportsDocument, type ImportKind } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { CSV_COLUMNS } from "@/lib/import-format";
import { nodesOf, pageArgs, toParams, type SearchParams } from "@/lib/list";
import { IMPORT_KIND, IMPORT_STATUS } from "@/lib/statuses";
import { isAdmin } from "@/lib/viewer";

// 取り込みの一覧と開始。品目と単価の取り込みは admin に限り、在庫の取り込みは役割を問わない
// (docs/architecture/graphql-schema.md「役割による制限」)
export default async function ImportsPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = toParams(await searchParams);
  const [result, admin] = await Promise.all([query(SupplierImportsDocument, pageArgs(params)), isAdmin()]);
  const error = result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.kind === "error" ? result.message : null;
  const data = result.kind === "ok" ? result.data.supplier : null;
  const businessDate = data?.dashboard.businessDate ?? null;
  const rows = data ? nodesOf(data.imports) : [];
  const kinds: ImportKind[] = admin ? ["STOCKS", "ITEMS"] : ["STOCKS"];

  return (
    <section className="flex flex-col gap-8">
      <PageHeader title="取り込み" />

      <div className="space-y-4">
        <ImportUpload admin={admin} />
        <div className="text-muted-foreground space-y-2 text-[13px]">
          <p>CSV の 1 行目には、次の列名をこの順に並べます。列名が違うと、行を見ずに取り込み全体が失敗します。</p>
          {kinds.map((kind) => (
            <div key={kind}>
              <p className="text-foreground-2 font-medium">{IMPORT_KIND[kind]}</p>
              <code className="text-foreground break-all">{CSV_COLUMNS[kind].map((c) => c.name).join(",")}</code>
              <ul className="mt-1 list-disc pl-5">
                {CSV_COLUMNS[kind].map((c) => (
                  <li key={c.name}>
                    <code>{c.name}</code>：{c.note}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>

      <div className="space-y-4">
        <FilterBar count={data ? data.imports.totalCount : null}>
          <h2 className="text-base font-semibold">これまでの取り込み</h2>
        </FilterBar>
        {error || !data ? (
          <ListError>{error}</ListError>
        ) : (
          <>
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>開始日時</TableHead>
                    <TableHead>種類</TableHead>
                    <TableHead>状況</TableHead>
                    <TableHead numeric>行数</TableHead>
                    <TableHead numeric>反映</TableHead>
                    <TableHead numeric>失敗</TableHead>
                    <TableHead>終了日時</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.length === 0 && (
                    <TableRow data-testid="empty-row">
                      <TableCell colSpan={7} className="text-muted-foreground py-8 text-center">
                        取り込みはまだありません
                      </TableCell>
                    </TableRow>
                  )}
                  {rows.map((run) => (
                    <TableRow key={run.id} data-testid="list-row">
                      <TableCell>
                        <TextLink href={`/supplier/imports/${run.id}`} className="rounded-sm font-semibold">
                          <DateText iso={run.startedAt} businessDate={businessDate} withTime />
                        </TextLink>
                      </TableCell>
                      <TableCell>{IMPORT_KIND[run.kind]}</TableCell>
                      <TableCell>
                        <StatusBadge style={IMPORT_STATUS[run.status]} value={run.status} />
                      </TableCell>
                      <TableCell numeric>{run.totalRows ?? "—"}</TableCell>
                      <TableCell numeric>{run.appliedRows}</TableCell>
                      <TableCell numeric>{run.failedRows}</TableCell>
                      <TableCell>
                        <DateText iso={run.finishedAt} businessDate={businessDate} withTime />
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
            <Pagination pageInfo={data.imports.pageInfo} />
          </>
        )}
      </div>
    </section>
  );
}
