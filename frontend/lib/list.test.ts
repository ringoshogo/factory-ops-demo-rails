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
  sortArgs,
  sortHref,
  toParams,
} from "./list";

const FIELDS = ["ORDER_NO", "ORDER_DATE", "DUE_DATE", "STATUS"] as const;

const asc = <F extends string>(field: F) => ({ field, direction: "ASC" as const });
const desc = <F extends string>(field: F) => ({ field, direction: "DESC" as const });

describe("parseSort: URL の sort・dir を列の並びに読む", () => {
  it("列が 1 つの URL は、field を小文字にした値と向きを、1 つの列の並びに読む", () => {
    expect(parseSort(new URLSearchParams("sort=due_date&dir=asc"), FIELDS)).toEqual([asc("DUE_DATE")]);
    expect(parseSort(new URLSearchParams("sort=order_no&dir=desc"), FIELDS)).toEqual([desc("ORDER_NO")]);
  });

  it("コンマでつないだ sort と dir を、同じ位置どうしで組にして列の順に読む", () => {
    expect(parseSort(new URLSearchParams("sort=status,order_no,due_date&dir=asc,desc,asc"), FIELDS)).toEqual([
      asc("STATUS"),
      desc("ORDER_NO"),
      asc("DUE_DATE"),
    ]);
  });

  it("field の一覧に無い値・不正な向き・向きの無いものは既定の並び (空の並び)", () => {
    expect(parseSort(new URLSearchParams("sort=customer&dir=asc"), FIELDS)).toEqual([]);
    expect(parseSort(new URLSearchParams("sort=order_no&dir=up"), FIELDS)).toEqual([]);
    expect(parseSort(new URLSearchParams("sort=order_no"), FIELDS)).toEqual([]);
    expect(parseSort(new URLSearchParams("sort=order_no,customer&dir=asc,asc"), FIELDS)).toEqual([]);
    expect(parseSort(new URLSearchParams("sort=order_no,due_date&dir=asc,up"), FIELDS)).toEqual([]);
  });

  it("sort と dir の長さが違う並び・同じ列を 2 回含む並び・4 つ以上の並びは既定の並び", () => {
    expect(parseSort(new URLSearchParams("sort=order_no,due_date&dir=asc"), FIELDS)).toEqual([]);
    expect(parseSort(new URLSearchParams("sort=order_no&dir=asc,desc"), FIELDS)).toEqual([]);
    expect(parseSort(new URLSearchParams("sort=order_no,order_no&dir=asc,desc"), FIELDS)).toEqual([]);
    expect(parseSort(new URLSearchParams("sort=order_no,due_date,status,order_date&dir=asc,asc,asc,asc"), FIELDS)).toEqual([]);
    // 対照：3 つまでなら読む
    expect(parseSort(new URLSearchParams("sort=order_no,due_date,status&dir=asc,asc,asc"), FIELDS)).toHaveLength(3);
  });

  it("同じ名前の値が 2 つあれば既定の並び", () => {
    expect(parseSort(new URLSearchParams("sort=order_no&sort=due_date&dir=asc"), FIELDS)).toEqual([]);
  });
});

describe("sortArgs: 並びの 1 つ目を orderBy、2 つ目からを thenBy に写す", () => {
  it("既定の並びはどちらも渡さず、列が 1 つなら thenBy を渡さない", () => {
    expect(sortArgs([])).toEqual({ orderBy: null, thenBy: null });
    expect(sortArgs([asc("DUE_DATE")])).toEqual({ orderBy: asc("DUE_DATE"), thenBy: null });
    expect(sortArgs([asc("STATUS"), desc("ORDER_NO")])).toEqual({ orderBy: asc("STATUS"), thenBy: [desc("ORDER_NO")] });
  });
});

describe("nextSort: 見出しを押したときの次の並び", () => {
  it("Shift を押さなければ、同じ列は 昇順 → 降順 → 既定の並び、別の列はその列 1 つの昇順", () => {
    const ascending = nextSort([], "ORDER_NO", false);
    expect(ascending).toEqual([asc("ORDER_NO")]);
    const descending = nextSort(ascending, "ORDER_NO", false);
    expect(descending).toEqual([desc("ORDER_NO")]);
    expect(nextSort(descending, "ORDER_NO", false)).toEqual([]);
    expect(nextSort(descending, "DUE_DATE", false)).toEqual([asc("DUE_DATE")]);
    // 並びが 2 つ以上なら、Shift を押さなければ、並びにある列もその列 1 つの昇順にする (向きを進めるのは、並びがその列 1 つのときだけ)
    expect(nextSort([asc("STATUS"), desc("ORDER_NO")], "ORDER_NO", false)).toEqual([asc("ORDER_NO")]);
    expect(nextSort([asc("STATUS"), desc("ORDER_NO")], "STATUS", false)).toEqual([asc("STATUS")]);
  });

  it("Shift を押すと、並びに無い列を昇順で後ろに足し、並びにある列の向きだけを 昇順 → 降順 → 外す の順に進め、ほかの列の順と向きを保つ", () => {
    const two = nextSort([asc("STATUS")], "ORDER_NO", true);
    expect(two).toEqual([asc("STATUS"), asc("ORDER_NO")]);
    expect(nextSort(two, "ORDER_NO", true)).toEqual([asc("STATUS"), desc("ORDER_NO")]);
    expect(nextSort([asc("STATUS"), desc("ORDER_NO")], "ORDER_NO", true)).toEqual([asc("STATUS")]);
    expect(nextSort([desc("STATUS"), asc("ORDER_NO")], "STATUS", true)).toEqual([asc("ORDER_NO")]);
    expect(nextSort([asc("STATUS"), asc("ORDER_NO")], "STATUS", true)).toEqual([desc("STATUS"), asc("ORDER_NO")]);
    // 既定の並びで Shift を押すと、その列 1 つの昇順
    expect(nextSort([], "DUE_DATE", true)).toEqual([asc("DUE_DATE")]);
  });

  it("並びが 3 つのときに、並びに無い列を Shift を押して押しても変えない。並びにある列の向きは進める", () => {
    const three = [asc("STATUS"), desc("ORDER_NO"), asc("DUE_DATE")];
    expect(nextSort(three, "ORDER_DATE", true)).toEqual(three);
    expect(nextSort(three, "DUE_DATE", true)).toEqual([asc("STATUS"), desc("ORDER_NO"), desc("DUE_DATE")]);
  });
});

describe("sortHref: 並べ替えを差し替え、1 ページ目に戻す", () => {
  it("絞り込みを保ち、after を外し、sort・dir を小文字で書く。列が 1 つなら、いまと同じ文字列", () => {
    const params = new URLSearchParams("status=RECEIVED&after=abc");
    expect(sortHref("/supplier/sales-orders", params, [desc("DUE_DATE")])).toBe(
      "/supplier/sales-orders?status=RECEIVED&sort=due_date&dir=desc",
    );
  });

  it("列が 2 つ以上なら、sort と dir を列の順にコンマでつなぐ", () => {
    const href = sortHref("/x", new URLSearchParams(), [asc("STATUS"), desc("ORDER_NO")]);
    const url = new URL(href, "http://e");
    expect([url.searchParams.get("sort"), url.searchParams.get("dir")]).toEqual(["status,order_no", "asc,desc"]);
  });

  it("既定の並びに戻すと sort・dir を外す", () => {
    expect(sortHref("/x", new URLSearchParams("sort=order_no&dir=desc"), [])).toBe("/x");
  });

  it("parseSort と往復して同じ並べ替えになる", () => {
    const sort = [asc("ORDER_DATE"), desc("STATUS")];
    const href = sortHref("/x", new URLSearchParams(), sort);
    expect(parseSort(new URL(href, "http://e").searchParams, FIELDS)).toEqual(sort);
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
