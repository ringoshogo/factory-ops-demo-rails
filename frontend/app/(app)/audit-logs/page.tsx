import { AuditLogFilter } from "@/components/audit-log-filter";
import { DateText } from "@/components/date-text";
import { ErrorNotice } from "@/components/error-notice";
import { FilterBar } from "@/components/filter-bar";
import { ListError } from "@/components/list-error";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { auditLogVariables, parseAuditLogList } from "@/lib/audit-log-list";
import { ViewerAuditLogsDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { nodesOf, toParams, type SearchParams } from "@/lib/list";
import { isAdmin } from "@/lib/viewer";

// 監査ログ。自社の admin だけが読め、member には API が FORBIDDEN を返すので、member には呼ばずに文言を出す。
// 新しいものから 1 ページずつ読む。シードの直後は、イベントのジョブが書く受信の行だけが並ぶ
// (docs/architecture/graphql-schema.md「監査ログ」)
export default async function AuditLogsPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  if (!(await isAdmin())) {
    return (
      <section className="space-y-5">
        <PageHeader title="監査ログ" />
        <ErrorNotice data-testid="admin-only">管理者だけが見られます。</ErrorNotice>
      </section>
    );
  }

  const params = toParams(await searchParams);
  const q = parseAuditLogList(params);
  const result = await query(ViewerAuditLogsDocument, auditLogVariables(q, params));
  const error = result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.kind === "error" ? result.message : null;
  const data = result.kind === "ok" ? result.data : null;
  const businessDate = data?.supplier.dashboard.businessDate ?? null;
  const rows = data ? nodesOf(data.viewer.auditLogs) : [];

  return (
    <section className="space-y-5">
      <PageHeader title="監査ログ" />
      <AuditLogFilter q={q} />
      <FilterBar count={data ? data.viewer.auditLogs.totalCount : null}>{null}</FilterBar>

      {error || !data ? (
        <ListError>{error}</ListError>
      ) : (
        <>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>日時</TableHead>
                  <TableHead>操作</TableHead>
                  <TableHead>操作者</TableHead>
                  <TableHead>対象</TableHead>
                  <TableHead>相手</TableHead>
                  <TableHead>相関 ID</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.length === 0 && (
                  <TableRow data-testid="empty-row">
                    <TableCell colSpan={6} className="text-muted-foreground py-8 text-center">
                      該当する記録がありません
                    </TableCell>
                  </TableRow>
                )}
                {rows.map((log) => (
                  <TableRow key={`${log.correlationId}-${log.occurredAt}-${log.targetId}-${log.action}`} data-testid="list-row">
                    <TableCell>
                      <DateText iso={log.occurredAt} businessDate={businessDate} withTime />
                    </TableCell>
                    <TableCell className="font-medium">{log.action}</TableCell>
                    {/* イベントの受信は人の操作ではないので、操作者を持たない */}
                    <TableCell truncate>{log.actorName ?? "（イベントの受信）"}</TableCell>
                    <TableCell truncate className="text-muted-foreground">
                      {log.targetType} {log.targetId}
                    </TableCell>
                    <TableCell truncate>{log.counterparty?.name ?? "—"}</TableCell>
                    <TableCell truncate className="text-muted-foreground font-mono text-xs">
                      {log.correlationId}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
          <Pagination pageInfo={data.viewer.auditLogs.pageInfo} />
        </>
      )}
    </section>
  );
}
