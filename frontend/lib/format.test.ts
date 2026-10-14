import { describe, expect, it } from "vitest";
import type { PurchaseOrderStatus, SalesOrderStatus } from "@/lib/graphql/generated";
import { totalAmountText } from "./format";
import { PURCHASE_ORDER_STATUS, SALES_ORDER_STATUS } from "./statuses";

// codegen の型は値の一覧を持たないので、型がすべての値を鍵に求める状況の一覧から集める
const SALES_ORDER_STATUSES = Object.keys(SALES_ORDER_STATUS) as SalesOrderStatus[];
const PURCHASE_ORDER_STATUSES = Object.keys(PURCHASE_ORDER_STATUS) as PurchaseOrderStatus[];

// 作者の判断：照合待ち・確定待ちのまま取り消した伝票は、合計の欄に「取消」と出す。受注側の取消も発注側の取消も含む
const CANCELLED_SALES_ORDER: readonly SalesOrderStatus[] = ["CANCELLED"];
const CANCELLED_PURCHASE_ORDER: readonly PurchaseOrderStatus[] = ["CANCELLED", "SUPPLIER_CANCELLED"];

describe("totalAmountText", () => {
  it("合計があれば 3 桁区切りの円で出し、2^53 を超える値も丸めない", () => {
    expect(totalAmountText("1050", "salesOrder", "RECEIVED")).toBe("1,050 円");
    expect(totalAmountText("27670116110564327421", "purchaseOrder", "ACCEPTED")).toBe("27,670,116,110,564,327,421 円");
  });

  it("合計があれば、取り消した伝票でも金額で出す", () => {
    expect(totalAmountText("1050", "salesOrder", "CANCELLED")).toBe("1,050 円");
    expect(totalAmountText("1050", "purchaseOrder", "SUPPLIER_CANCELLED")).toBe("1,050 円");
  });

  it("合計が空なら 0 円にせず、取り消した受注は「取消」、ほかの受注は「照合待ち」を出す", () => {
    expect(totalAmountText(null, "salesOrder", "CANCELLED")).toBe("取消");
    for (const status of SALES_ORDER_STATUSES) {
      expect(totalAmountText(null, "salesOrder", status), status).toBe(CANCELLED_SALES_ORDER.includes(status) ? "取消" : "照合待ち");
    }
    // 対照：0 円の合計は空と区別して金額で出す
    expect(totalAmountText("0", "salesOrder", "AWAITING_PART_MATCH")).toBe("0 円");
  });

  it("合計が空なら、取り消した発注は「取消」、ほかの発注は「確定待ち」を出す", () => {
    for (const status of PURCHASE_ORDER_STATUSES) {
      expect(totalAmountText(null, "purchaseOrder", status), status).toBe(
        CANCELLED_PURCHASE_ORDER.includes(status) ? "取消" : "確定待ち",
      );
    }
    // 空振りしない：取り消した状況も、取り消していない状況も、すべての値の中にある
    expect(PURCHASE_ORDER_STATUSES.filter((s) => CANCELLED_PURCHASE_ORDER.includes(s))).toHaveLength(2);
    expect(SALES_ORDER_STATUSES.filter((s) => CANCELLED_SALES_ORDER.includes(s))).toHaveLength(1);
  });
});
