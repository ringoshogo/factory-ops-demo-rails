import { notFound } from "next/navigation";
import { TextLink } from "@/components/app-link";
import { DateText } from "@/components/date-text";
import { ErrorNotice } from "@/components/error-notice";
import { ImportRefresher } from "@/components/import-refresher";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { StatusBadge } from "@/components/status-badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { SupplierImportDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { nodesOf, pageArgs, toParams, type SearchParams } from "@/lib/list";
import { IMPORT_FINISHED, IMPORT_KIND, IMPORT_STATUS } from "@/lib/statuses";

// 取り込みの進み具合。終わるまでは数秒ごとに読み直し、失敗した行を行番号の順に 1 ページずつ出す。
// 失敗した行のほかの行は反映済みで、一部失敗でも反映を戻さない
export default async function ImportPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const { id } = await params;
  const search = toParams(await searchParams);
  const result = await query(SupplierImportDocument, { id, ...pageArgs(search) });
  if (result.kind !== "ok") {
    return (
      <section className="space-y-5">
        <PageHeader title="取り込み" />
        <ErrorNotice data-testid="detail-error">
          {result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.message}
        </ErrorNotice>
      </section>
    );
  }
  const run = result.data.supplier.import;
  if (!run) notFound();
  const businessDate = result.data.supplier.dashboard.businessDate;
  const finished = IMPORT_FINISHED.includes(run.status);
  const errors = nodesOf(run.rowErrors);

  return (
    <section className="flex flex-col gap-8">
      <ImportRefresher finished={finished} />
      <PageHeader
        title={`取り込み（${IMPORT_KIND[run.kind]}）`}
        description={<TextLink href="/supplier/imports">取り込みの一覧へ</TextLink>}
      />

      <dl className="grid max-w-2xl grid-cols-[8rem_1fr] gap-x-6 gap-y-3 text-sm">
        <dt className="text-muted-foreground">状況</dt>
        <dd data-testid="import-status" data-status={run.status}>
          <StatusBadge style={IMPORT_STATUS[run.status]} value={run.status} />
          {!finished && <span className="text-muted-foreground ml-2 text-[13px]">終わるまで自動で読み直します</span>}
        </dd>
        <dt className="text-muted-foreground">行数</dt>
        <dd className="tabular-nums">{run.totalRows ?? "置き場へ写し終えると出ます"}</dd>
        <dt className="text-muted-foreground">反映した行</dt>
        <dd className="tabular-nums">{run.appliedRows}</dd>
        <dt className="text-muted-foreground">失敗した行</dt>
        <dd className="tabular-nums">{run.failedRows}</dd>
        <dt className="text-muted-foreground">開始</dt>
        <dd>
          <DateText iso={run.startedAt} businessDate={businessDate} withTime />
        </dd>
        <dt className="text-muted-foreground">終了</dt>
        <dd>
          <DateText iso={run.finishedAt} businessDate={businessDate} withTime />
        </dd>
      </dl>

      <div className="space-y-3">
        <h2 className="text-base font-semibold">失敗した行（{run.rowErrors.totalCount} 件）</h2>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead numeric>行番号</TableHead>
              <TableHead>理由</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {errors.length === 0 && (
              <TableRow data-testid="empty-row">
                <TableCell colSpan={2} className="text-muted-foreground py-8 text-center">
                  失敗した行はありません
                </TableCell>
              </TableRow>
            )}
            {errors.map((e) => (
              <TableRow key={e.rowNumber} data-testid="row-error">
                <TableCell numeric className="w-24">
                  {e.rowNumber}
                </TableCell>
                {/* 理由は「列名: 理由」の形の API の文言をそのまま出す */}
                <TableCell truncate="wide">{e.message}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        <Pagination pageInfo={run.rowErrors.pageInfo} />
      </div>
    </section>
  );
}
