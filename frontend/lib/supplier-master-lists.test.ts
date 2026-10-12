import { describe, expect, it } from "vitest";

import {
  itemListVariables,
  partMappingVariables,
  stockListVariables,
  stockMovementVariables,
} from "./supplier-master-lists";

const p = (query: string) => new URLSearchParams(query);

describe("品目の一覧の変数", () => {
  it("検索の語を filter.keyword に、並べ替えを orderBy に写す", () => {
    expect(itemListVariables(p("q=ITM&sort=name&dir=desc&after=Mg"))).toEqual({
      first: 20,
      after: "Mg",
      orderBy: { field: "NAME", direction: "DESC" },
      filter: { keyword: "ITM" },
    });
  });

  it("空白だけの語と語の無いものは絞らない。API で並べられない列は既定の並び", () => {
    expect(itemListVariables(p("q=%20%20")).filter).toBeNull();
    expect(itemListVariables(p("")).filter).toBeNull();
    expect(itemListVariables(p("sort=unit_price&dir=asc")).orderBy).toBeNull();
  });
});

describe("在庫の一覧の変数", () => {
  it("below=1 のときだけ安全在庫を下回る在庫に絞る", () => {
    expect(stockListVariables(p("below=1")).filter).toEqual({ belowSafetyStock: true });
    expect(stockListVariables(p("below=0")).filter).toBeNull();
    expect(stockListVariables(p("")).filter).toBeNull();
  });

  it("orderBy の field のすべてを並べ替えに使える。品目のコードと名前では並べない", () => {
    for (const field of ["on_hand", "allocated", "available", "safety_stock"]) {
      expect(stockListVariables(p(`sort=${field}&dir=asc`)).orderBy?.field).toBe(field.toUpperCase());
    }
    expect(stockListVariables(p("sort=code&dir=asc")).orderBy).toBeNull();
  });
});

describe("在庫の移動履歴の変数", () => {
  it("種類と品目で絞り、知らない種類は除く", () => {
    expect(stockMovementVariables(p("type=INBOUND&type=BOGUS&item=i1"))).toEqual({
      first: 20,
      after: null,
      itemId: "i1",
      filter: { types: ["INBOUND"] },
    });
    expect(stockMovementVariables(p("type=BOGUS")).filter).toBeNull();
  });
});

describe("品番の対応表の変数", () => {
  it("取引先で絞る。無ければ絞らない", () => {
    expect(partMappingVariables(p("customer=t1")).customerTenantId).toBe("t1");
    expect(partMappingVariables(p("")).customerTenantId).toBeNull();
  });
});
