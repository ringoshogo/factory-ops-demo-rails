import { describe, expect, it } from "vitest";

import { parseSalesOrderList, salesOrderListVariables } from "./sales-order-list";

const parse = (query: string) => {
  const params = new URLSearchParams(query);
  const q = parseSalesOrderList(params);
  return { q, variables: salesOrderListVariables(q, params) };
};

describe("受注一覧の URL を変数に写す", () => {
  it("タブの状況のまとまりで一覧を絞り、タブごとの件数の変数は同じ取引先と受注日で絞る", () => {
    const { q, variables } = parse("tab=open&customer=t1&from=2026-10-01");
    expect(q.tab).toBe("open");
    expect(variables.filter).toEqual({
      customerTenantId: "t1",
      orderDateFrom: "2026-10-01",
      orderDateTo: null,
      statuses: ["AWAITING_PART_MATCH", "RECEIVED", "PARTIALLY_ALLOCATED", "ALLOCATED"],
    });
    expect(variables.allFilter).toEqual({ customerTenantId: "t1", orderDateFrom: "2026-10-01", orderDateTo: null });
    expect(variables.shippedFilter.statuses).toEqual(["SHIPPED"]);
    expect(variables.inspectedFilter.statuses).toEqual(["INSPECTED"]);
    expect(variables.cancelledFilter.statuses).toEqual(["CANCELLED"]);
  });

  it("状況を選ぶと一覧はその状況だけに絞り、タブの件数の変数は変えない", () => {
    const { variables } = parse("tab=open&status=RECEIVED");
    expect(variables.filter.statuses).toEqual(["RECEIVED"]);
    expect(variables.openFilter.statuses).toHaveLength(4);
  });

  it("タブの外の状況を選んでいれば「すべて」のタブにする", () => {
    expect(parse("tab=open&status=SHIPPED").q.tab).toBe("all");
  });

  it("不正なタブ・状況・日付は絞らない", () => {
    const { q, variables } = parse("tab=bogus&status=BOGUS&from=yesterday");
    expect(q.tab).toBe("all");
    expect(variables.filter).toEqual({ customerTenantId: null, orderDateFrom: null, orderDateTo: null });
  });

  it("並べ替えと次のページの位置を変数に写す", () => {
    const { variables } = parse("sort=due_date&dir=desc&after=Mg");
    expect(variables.orderBy).toEqual({ field: "DUE_DATE", direction: "DESC" });
    expect(variables.first).toBe(20);
    expect(variables.after).toBe("Mg");
  });
});
