import type { ItemOrderField, StockMovementType, StockOrderField } from "@/lib/graphql/generated";
import { pageArgs, parseEnumList, parseSort, single, type Sort } from "@/lib/list";

/**
 * 受注側の品目・在庫・移動履歴・品番の対応表の一覧の URL の値を、GraphQL の変数に写す。サーバー部品 (一覧) と
 * クライアント部品 (絞り込み) の両方が import するので、next/headers を読み込まない。
 */

export const ITEM_SORT_FIELDS: readonly ItemOrderField[] = ["CODE", "NAME"];

/** 品目の一覧。検索の語は API が前後の空白を除くので、空白だけなら送らない。 */
export function itemListVariables(params: URLSearchParams) {
  const keyword = single(params, "q")?.trim() ?? "";
  const sort: Sort<ItemOrderField> = parseSort(params, ITEM_SORT_FIELDS);
  return {
    ...pageArgs(params),
    orderBy: sort,
    filter: keyword === "" ? null : { keyword },
  };
}

export const STOCK_SORT_FIELDS: readonly StockOrderField[] = ["ON_HAND", "ALLOCATED", "AVAILABLE", "SAFETY_STOCK"];

/**
 * 在庫の一覧。`below=1` のときだけ、有効在庫が安全在庫より小さい在庫に絞る。ダッシュボードの「安全在庫を下回る在庫」と
 * 同じ条件を API が持つので、件数がダッシュボードと一致する。
 */
export function stockListVariables(params: URLSearchParams) {
  return {
    ...pageArgs(params),
    orderBy: parseSort(params, STOCK_SORT_FIELDS),
    filter: single(params, "below") === "1" ? { belowSafetyStock: true } : null,
  };
}

export const STOCK_MOVEMENT_TYPES: readonly StockMovementType[] = ["INBOUND", "OUTBOUND", "ALLOCATE", "DEALLOCATE", "SHIP"];

/** 在庫の移動履歴。種類 (`type`) と品目 (`item`) で絞る。 */
export function stockMovementVariables(params: URLSearchParams) {
  const types = parseEnumList(params, "type", STOCK_MOVEMENT_TYPES);
  return {
    ...pageArgs(params),
    itemId: single(params, "item"),
    filter: types ? { types } : null,
  };
}

/** 品番の対応表。取引先 (`customer`) で絞る。 */
export function partMappingVariables(params: URLSearchParams) {
  return { ...pageArgs(params), customerTenantId: single(params, "customer"), itemKeyword: single(params, "item_q") };
}
