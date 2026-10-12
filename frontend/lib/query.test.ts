import { describe, expect, it } from "vitest";

import { patchHref } from "./query";

describe("patchHref: 今の URL の他のキーを保ち、変える項目だけを差し替える", () => {
  it("値は既存のキーを置き換え、無いキーは足し、他のキーは順を含めて保つ", () => {
    const params = new URLSearchParams("sort=order_no&dir=desc&status=受注済&customer_id=c1");
    const href = patchHref("/orders", params, { status: "出荷済", from: "2026-10-01" });
    expect(href).toBe(
      `/orders?${new URLSearchParams("sort=order_no&dir=desc&status=出荷済&customer_id=c1&from=2026-10-01").toString()}`,
    );
  });

  it("null はそのキーを外す。同じ名前のキーが複数あれば全部外す", () => {
    const params = new URLSearchParams("tab=open&status=a&status=b&sort=qty&dir=asc");
    expect(patchHref("/orders", params, { status: null })).toBe("/orders?tab=open&sort=qty&dir=asc");
  });

  it("値を当てると同じ名前の複数の値は 1 つにまとまる", () => {
    const params = new URLSearchParams("status=a&status=b&q=x");
    expect(patchHref("/orders", params, { status: "c" })).toBe("/orders?status=c&q=x");
  });

  it("無いキーを null で外しても他は変わらない", () => {
    expect(patchHref("/stocks", new URLSearchParams("q=ITM"), { page: null })).toBe("/stocks?q=ITM");
  });

  it("クエリが空になるときは ? を付けない", () => {
    expect(patchHref("/items", new URLSearchParams("sort=name&dir=asc"), { sort: null, dir: null })).toBe("/items");
    expect(patchHref("/items", new URLSearchParams(), {})).toBe("/items");
  });

  it("差し替えが空なら今のクエリをそのまま返す", () => {
    expect(patchHref("/orders", new URLSearchParams("a=1&b=2"), {})).toBe("/orders?a=1&b=2");
  });

  it("受け取った params を変えない (useSearchParams() の値は読み取り専用)", () => {
    const params = new URLSearchParams("tab=open&status=受注済&sort=qty&dir=asc");
    const before = params.toString();
    patchHref("/orders", params, { status: null, tab: "shipped", from: "2026-10-01" });
    expect(params.toString()).toBe(before);
  });
});
