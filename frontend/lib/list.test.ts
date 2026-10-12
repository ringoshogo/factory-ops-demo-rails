import { describe, expect, it } from "vitest";

import {
  firstPageHref,
  nextPageHref,
  nextSort,
  PAGE_SIZE,
  pageArgs,
  parseDate,
  parseEnumList,
  parseSort,
  sortHref,
  toParams,
} from "./list";

const FIELDS = ["ORDER_NO", "ORDER_DATE", "DUE_DATE"] as const;

describe("parseSort: URL の sort・dir を orderBy に写す", () => {
  it("field を小文字にした値と向きを、orderBy の field と direction に写す", () => {
    expect(parseSort(new URLSearchParams("sort=due_date&dir=asc"), FIELDS)).toEqual({ field: "DUE_DATE", direction: "ASC" });
    expect(parseSort(new URLSearchParams("sort=order_no&dir=desc"), FIELDS)).toEqual({ field: "ORDER_NO", direction: "DESC" });
  });

  it("field の一覧に無い値・不正な向き・向きの無いものは既定の並び (null)", () => {
    expect(parseSort(new URLSearchParams("sort=customer&dir=asc"), FIELDS)).toBeNull();
    expect(parseSort(new URLSearchParams("sort=order_no&dir=up"), FIELDS)).toBeNull();
    expect(parseSort(new URLSearchParams("sort=order_no"), FIELDS)).toBeNull();
  });

  it("同じ名前の値が 2 つあれば既定の並び", () => {
    expect(parseSort(new URLSearchParams("sort=order_no&sort=due_date&dir=asc"), FIELDS)).toBeNull();
  });
});

describe("nextSort: 見出しを押したときの次の並べ替え", () => {
  it("同じ列は 昇順 → 降順 → 既定の並び、別の列は昇順", () => {
    const asc = nextSort(null, "ORDER_NO");
    expect(asc).toEqual({ field: "ORDER_NO", direction: "ASC" });
    const desc = nextSort(asc, "ORDER_NO");
    expect(desc).toEqual({ field: "ORDER_NO", direction: "DESC" });
    expect(nextSort(desc, "ORDER_NO")).toBeNull();
    expect(nextSort(desc, "DUE_DATE")).toEqual({ field: "DUE_DATE", direction: "ASC" });
  });
});

describe("sortHref: 並べ替えを差し替え、1 ページ目に戻す", () => {
  it("絞り込みを保ち、after を外し、sort・dir を小文字で書く", () => {
    const params = new URLSearchParams("status=RECEIVED&after=abc");
    expect(sortHref("/supplier/sales-orders", params, { field: "DUE_DATE", direction: "DESC" })).toBe(
      "/supplier/sales-orders?status=RECEIVED&sort=due_date&dir=desc",
    );
  });

  it("既定の並びに戻すと sort・dir を外す", () => {
    expect(sortHref("/x", new URLSearchParams("sort=order_no&dir=desc"), null)).toBe("/x");
  });

  it("parseSort と往復して同じ並べ替えになる", () => {
    const href = sortHref("/x", new URLSearchParams(), { field: "ORDER_DATE", direction: "ASC" });
    expect(parseSort(new URL(href, "http://e").searchParams, FIELDS)).toEqual({ field: "ORDER_DATE", direction: "ASC" });
  });
});

describe("ページの引数と URL", () => {
  it("1 ページは 20 件で、after は URL の値をそのまま渡す", () => {
    expect(PAGE_SIZE).toBe(20);
    expect(pageArgs(new URLSearchParams("after=Mg"))).toEqual({ first: 20, after: "Mg" });
    expect(pageArgs(new URLSearchParams())).toEqual({ first: 20, after: null });
  });

  it("次のページは after だけを差し替え、最初のページは after を外す", () => {
    const params = new URLSearchParams("sort=name&dir=asc&after=a1");
    expect(nextPageHref("/supplier/items", params, "b2")).toBe("/supplier/items?sort=name&dir=asc&after=b2");
    expect(firstPageHref("/supplier/items", params)).toBe("/supplier/items?sort=name&dir=asc");
  });
});

describe("絞り込みの値", () => {
  it("許した値だけを残し、残らなければ null (絞らない)", () => {
    const params = new URLSearchParams("status=RECEIVED&status=BOGUS&status=SHIPPED");
    expect(parseEnumList(params, "status", ["RECEIVED", "SHIPPED", "CANCELLED"])).toEqual(["RECEIVED", "SHIPPED"]);
    expect(parseEnumList(new URLSearchParams("status=BOGUS"), "status", ["RECEIVED"])).toBeNull();
  });

  it("日付は YYYY-MM-DD の形だけを受ける", () => {
    expect(parseDate(new URLSearchParams("from=2026-10-01"), "from")).toBe("2026-10-01");
    expect(parseDate(new URLSearchParams("from=abc"), "from")).toBeNull();
  });

  it("toParams は同じ名前の複数の値を保つ", () => {
    expect(toParams({ status: ["A", "B"], q: "x", none: undefined }).toString()).toBe("status=A&status=B&q=x");
  });
});
