import { describe, expect, it } from "vitest";

import { parseShipmentRequestList, shipmentRequestListVariables } from "./shipment-request-list";

const parse = (query: string) => {
  const params = new URLSearchParams(query);
  const q = parseShipmentRequestList(params);
  return { q, variables: shipmentRequestListVariables(q, params) };
};

describe("出荷依頼一覧の URL を変数に写す", () => {
  it("タブの状況のまとまりで一覧を絞り、タブごとの件数の変数はタブの状況だけで絞る", () => {
    const { q, variables } = parse("tab=open");
    expect(q.tab).toBe("open");
    expect(variables.filter).toEqual({ statuses: ["READY", "INSTRUCTED", "ON_HOLD"] });
    expect(variables.allFilter).toEqual({});
    expect(variables.shippedFilter).toEqual({ statuses: ["SHIPPED"] });
    expect(variables.cancelledFilter).toEqual({ statuses: ["CANCELLED"] });
  });

  it("状況を選ぶと一覧はその状況だけに絞り、タブの外の状況なら「すべて」のタブにする", () => {
    expect(parse("tab=open&status=INSTRUCTED").variables.filter).toEqual({ statuses: ["INSTRUCTED"] });
    expect(parse("tab=open&status=SHIPPED").q.tab).toBe("all");
  });

  it("並べ替えは出荷期限だけを受け、ほかの列の値は既定の並びにする", () => {
    expect(parse("sort=due_date&dir=asc").variables.orderBy).toEqual({ field: "DUE_DATE", direction: "ASC" });
    expect(parse("sort=order_no&dir=asc").variables.orderBy).toBeNull();
  });

  it("不正なタブと状況は絞らない", () => {
    const { q, variables } = parse("tab=bogus&status=BOGUS");
    expect(q.tab).toBe("all");
    expect(variables.filter).toEqual({});
  });
});
