import { describe, expect, it } from "vitest";

import { PURCHASE_ORDER_STATUS_ORDER } from "./statuses";
import { PURCHASE_ORDER_TABS, parsePurchaseOrderList, purchaseOrderListVariables } from "./purchase-order-list";

const parse = (query: string) => {
  const params = new URLSearchParams(query);
  const q = parsePurchaseOrderList(params);
  return { q, variables: purchaseOrderListVariables(q, params) };
};

describe("発注一覧の URL を変数に写す", () => {
  it("入荷予定のタブは入荷予定の状況だけで絞り、タブごとの件数の変数は同じ取引先と発注日で絞る", () => {
    const { q, variables } = parse("tab=inbound&supplier=s1&to=2026-10-31");
    expect(q.tab).toBe("inbound");
    expect(variables.filter).toEqual({
      supplierTenantId: "s1",
      orderDateFrom: null,
      orderDateTo: "2026-10-31",
      statuses: ["INBOUND"],
    });
    expect(variables.allFilter).toEqual({ supplierTenantId: "s1", orderDateFrom: null, orderDateTo: "2026-10-31" });
    expect(variables.openFilter.statuses).toEqual(["SENT", "AWAITING_SUPPLIER_CONFIRMATION", "ACCEPTED"]);
    expect(variables.inspectedFilter.statuses).toEqual(["INSPECTED"]);
    expect(variables.cancelledFilter.statuses).toEqual(["CANCELLED", "SUPPLIER_CANCELLED"]);
  });

  it("状況を選ぶと一覧はその状況だけに絞り、タブの件数の変数は変えない", () => {
    const { variables } = parse("tab=cancelled&status=SUPPLIER_CANCELLED");
    expect(variables.filter.statuses).toEqual(["SUPPLIER_CANCELLED"]);
    expect(variables.cancelledFilter.statuses).toHaveLength(2);
  });

  it("タブの外の状況を選んでいれば「すべて」のタブにする", () => {
    expect(parse("tab=inbound&status=ACCEPTED").q.tab).toBe("all");
  });

  it("不正なタブ・状況・日付は絞らない", () => {
    const { q, variables } = parse("tab=bogus&status=BOGUS&from=yesterday");
    expect(q.tab).toBe("all");
    expect(variables.filter).toEqual({ supplierTenantId: null, orderDateFrom: null, orderDateTo: null });
  });

  it("並べ替えと次のページの位置を変数に写す", () => {
    const { variables } = parse("sort=desired_delivery_on&dir=asc&after=Mg");
    expect(variables.orderBy).toEqual({ field: "DESIRED_DELIVERY_ON", direction: "ASC" });
    expect(variables.first).toBe(20);
    expect(variables.after).toBe("Mg");
  });

  it("「すべて」以外のタブの状況は重ならず、合わせると発注のすべての状況になる", () => {
    const statuses = PURCHASE_ORDER_TABS.flatMap((t) => t.statuses ?? []);
    expect(new Set(statuses).size).toBe(statuses.length);
    expect([...statuses].sort()).toEqual([...PURCHASE_ORDER_STATUS_ORDER].sort());
  });
});
