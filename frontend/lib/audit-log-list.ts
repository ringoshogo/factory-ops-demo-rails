import type { AuditLogFilter } from "@/lib/graphql/generated";
import { pageArgs, parseDate, single } from "@/lib/list";

/**
 * 監査ログの画面の URL を、viewer.auditLogs の変数に写す。期間は日付で受け、API の時刻の絞り込み
 * (occurredFrom 以上・occurredTo 未満) に、日本時間のその日の始まりと、終わりの日の翌日の始まりで渡す。
 */
export type AuditLogListQuery = { action: string; correlationId: string; from: string | null; to: string | null };

export function parseAuditLogList(params: URLSearchParams): AuditLogListQuery {
  return {
    action: single(params, "action")?.trim() ?? "",
    correlationId: single(params, "correlation")?.trim() ?? "",
    from: parseDate(params, "from"),
    to: parseDate(params, "to"),
  };
}

/** 日本時間の日付の 0 時。days だけ後ろへずらせる。 */
function tokyoMidnight(date: string, days = 0): string {
  const at = new Date(`${date}T00:00:00+09:00`);
  at.setUTCDate(at.getUTCDate() + days);
  return at.toISOString();
}

export function auditLogVariables(q: AuditLogListQuery, params: URLSearchParams) {
  const filter: AuditLogFilter = {
    action: q.action || null,
    correlationId: q.correlationId || null,
    occurredFrom: q.from ? tokyoMidnight(q.from) : null,
    occurredTo: q.to ? tokyoMidnight(q.to, 1) : null,
  };
  return { ...pageArgs(params), filter };
}
