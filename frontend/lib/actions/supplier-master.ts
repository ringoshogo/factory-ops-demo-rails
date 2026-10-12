"use server";

import type { FormState } from "@/lib/form-state";
import {
  AdjustStockDocument,
  CorrectItemPriceDocument,
  EstablishPartnershipDocument,
  GrantPermissionDocument,
  RegisterPartMappingDocument,
  RevokePartnershipDocument,
  SaveItemDocument,
  ScheduleItemPriceDocument,
  SetItemPublishedDocument,
  WithdrawPermissionDocument,
  type PartnershipPermission,
  type StockAdjustmentType,
} from "@/lib/graphql/generated";
import { mutate } from "@/lib/graphql/request";
import { settle } from "@/lib/graphql/user-errors";

// 受注側の品目・在庫・品番の対応表・取引関係の操作。入力欄の name は GraphQL の入力の名前と同じにし、
// UserError の path がそのまま入力欄の鍵になるようにする

function str(form: FormData, key: string): string {
  return String(form.get(key) ?? "").trim();
}

/**
 * 整数の入力。GraphQL の Int と BigInt に数でない値を送ると、入力の誤りではなくトップレベルのエラーになり、どの欄の
 * 誤りかを返せない。そのため形だけを送る前に確かめ、範囲は API の検証に任せる。
 */
function integer(form: FormData, key: string): string | null {
  const value = str(form, key);
  return /^-?\d+$/.test(value) ? value : null;
}

function invalid(key: string, message = "整数で入力してください"): FormState {
  return { status: "error", fieldErrors: { [key]: message } };
}

const ITEM_PATHS = ["/supplier/items", "/supplier/stocks", "/supplier/part-mappings"];

/** 品目の登録と更新。コードが同じ品目があれば名前・単位・税率を書き換える。既存の品目の単価はこの操作では変えない。 */
export async function saveItem(_prev: FormState, form: FormData): Promise<FormState> {
  const unitPrice = integer(form, "unitPrice");
  if (unitPrice === null) return invalid("unitPrice");
  const taxRatePercent = integer(form, "taxRatePercent");
  if (taxRatePercent === null) return invalid("taxRatePercent");
  const result = await mutate(SaveItemDocument, {
    input: {
      code: str(form, "code"),
      name: str(form, "name"),
      unit: str(form, "unit"),
      unitPrice,
      taxRatePercent: Number(taxRatePercent),
    },
  });
  const id = result.kind === "ok" ? result.data.saveItem.item?.id : undefined;
  return settle(result, (d) => d.saveItem, [...ITEM_PATHS, ...(id ? [`/supplier/items/${id}`] : [])]);
}

/** カタログへの公開と取り下げ。公開した品目だけが、発注側のカタログに出る。 */
export async function setItemPublished(_prev: FormState, form: FormData): Promise<FormState> {
  const itemId = str(form, "itemId");
  const result = await mutate(SetItemPublishedDocument, {
    input: { itemId, published: str(form, "published") === "true" },
  });
  return settle(result, (d) => d.setItemPublished, [...ITEM_PATHS, `/supplier/items/${itemId}`]);
}

/** 単価の改定の予約。改定日から新しい単価が効き、それより前の受注の単価は変わらない。 */
export async function scheduleItemPrice(_prev: FormState, form: FormData): Promise<FormState> {
  const itemId = str(form, "itemId");
  const unitPrice = integer(form, "unitPrice");
  if (unitPrice === null) return invalid("unitPrice");
  const result = await mutate(ScheduleItemPriceDocument, {
    input: { itemId, unitPrice, effectiveOn: str(form, "effectiveOn") },
  });
  return settle(result, (d) => d.scheduleItemPrice, [`/supplier/items/${itemId}`, "/supplier/items"]);
}

/** 入力の誤りの訂正。行を書き換えず、記録期間を閉じて新しい行を足すので、訂正の前に信じていた単価も履歴に残る。 */
export async function correctItemPrice(_prev: FormState, form: FormData): Promise<FormState> {
  const itemId = str(form, "itemId");
  const unitPrice = integer(form, "unitPrice");
  if (unitPrice === null) return invalid("unitPrice");
  const result = await mutate(CorrectItemPriceDocument, {
    input: { itemPriceId: str(form, "itemPriceId"), unitPrice, reason: str(form, "reason") },
  });
  return settle(result, (d) => d.correctItemPrice, [`/supplier/items/${itemId}`, "/supplier/items"]);
}

/** 入庫と出庫。出庫で現在庫が引当を下回るかどうかは、表示が古いことがあるので画面で判定せず API に任せる。 */
export async function adjustStock(_prev: FormState, form: FormData): Promise<FormState> {
  const quantity = integer(form, "quantity");
  if (quantity === null) return invalid("quantity");
  const type: StockAdjustmentType = str(form, "type") === "OUTBOUND" ? "OUTBOUND" : "INBOUND";
  const reason = str(form, "reason");
  const result = await mutate(AdjustStockDocument, {
    input: { itemId: str(form, "itemId"), type, quantity: Number(quantity), reason: reason === "" ? null : reason },
  });
  return settle(result, (d) => d.adjustStock, ["/supplier/stocks", "/supplier/items", "/supplier/dashboard"]);
}

/** 得意先品番と自社の品目の対応を登録する。照合待ちの受注は、対応がそろうとイベントで受注確定へ進む。 */
export async function registerPartMapping(_prev: FormState, form: FormData): Promise<FormState> {
  const result = await mutate(RegisterPartMappingDocument, {
    input: {
      customerTenantId: str(form, "customerTenantId"),
      customerPartNumber: str(form, "customerPartNumber"),
      itemId: str(form, "itemId"),
    },
  });
  return settle(result, (d) => d.registerPartMapping, ["/supplier/part-mappings", "/supplier/sales-orders", "/supplier/dashboard"]);
}

const PARTNERSHIP_PATHS = ["/supplier/partnerships", "/supplier/sales-orders", "/supplier/dashboard"];

/** 発注側テナントの取引用コードで取引関係を結ぶ。相手はコードを業務の外で受注側へ伝える。 */
export async function establishPartnership(_prev: FormState, form: FormData): Promise<FormState> {
  const result = await mutate(EstablishPartnershipDocument, { input: { partnerCode: str(form, "partnerCode") } });
  // 取引用コードに当たる相手が無いときの NOT_FOUND は、伝票を ID で引いたときと違い、利用者が入れた値の誤りである。
  // 見つからない画面へ移すと入れ直せないので、入力欄の下に出す
  if (result.kind === "ok" && result.data.establishPartnership.errors.some((e) => e.code === "NOT_FOUND")) {
    return { status: "error", fieldErrors: { partnerCode: "この取引用コードの相手は見つかりません。コードを確かめてください。" } };
  }
  return settle(result, (d) => d.establishPartnership, PARTNERSHIP_PATHS);
}

/** 失効させた取引関係は元に戻せない。取引を再開するには、改めて取引関係を結ぶ。 */
export async function revokePartnership(_prev: FormState, form: FormData): Promise<FormState> {
  const result = await mutate(RevokePartnershipDocument, { input: { partnershipId: str(form, "partnershipId") } });
  return settle(result, (d) => d.revokePartnership, PARTNERSHIP_PATHS);
}

const PERMISSIONS: readonly PartnershipPermission[] = ["VIEW_CATALOG", "PLACE_ORDERS", "VIEW_SHIPMENTS"];

function permission(form: FormData): PartnershipPermission | null {
  const value = str(form, "permission");
  return PERMISSIONS.find((p) => p === value) ?? null;
}

/** 権限の付与。付与済みの権限の付与は、何もせず成功になる。 */
export async function grantPermission(_prev: FormState, form: FormData): Promise<FormState> {
  const value = permission(form);
  if (!value) return { status: "error", message: "権限を選んでください" };
  const result = await mutate(GrantPermissionDocument, {
    input: { partnershipId: str(form, "partnershipId"), permission: value },
  });
  return settle(result, (d) => d.grantPermission, PARTNERSHIP_PATHS);
}

/** 権限の撤回。付与していない権限の撤回は、何もせず成功になる。 */
export async function withdrawPermission(_prev: FormState, form: FormData): Promise<FormState> {
  const value = permission(form);
  if (!value) return { status: "error", message: "権限を選んでください" };
  const result = await mutate(WithdrawPermissionDocument, {
    input: { partnershipId: str(form, "partnershipId"), permission: value },
  });
  return settle(result, (d) => d.withdrawPermission, PARTNERSHIP_PATHS);
}
