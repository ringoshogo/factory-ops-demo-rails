import { describe, expect, it } from "vitest";

import { auditLogVariables, parseAuditLogList } from "./audit-log-list";

const variables = (query: string) => {
  const params = new URLSearchParams(query);
  return auditLogVariables(parseAuditLogList(params), params);
};

describe("監査ログの URL を変数に写す", () => {
  it("期間は日本時間の始まりの日の 0 時から、終わりの日の翌日の 0 時の手前まで", () => {
    expect(variables("from=2026-10-01&to=2026-10-02").filter).toEqual({
      action: null,
      correlationId: null,
      occurredFrom: "2026-09-30T15:00:00.000Z",
      occurredTo: "2026-10-02T15:00:00.000Z",
    });
  });

  it("操作と相関 ID は前後の空白を除き、空なら絞らない", () => {
    const { filter } = variables("action=+partnership.revoke+&correlation=");
    expect(filter.action).toBe("partnership.revoke");
    expect(filter.correlationId).toBeNull();
  });

  it("不正な日付は絞らず、1 ページは 20 件で after を渡す", () => {
    const v = variables("from=yesterday&after=Mg");
    expect(v.filter.occurredFrom).toBeNull();
    expect(v.first).toBe(20);
    expect(v.after).toBe("Mg");
  });
});
