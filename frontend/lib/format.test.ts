import { describe, expect, it } from "vitest";
import type { PurchaseOrderStatus, PurchaseOrderTimelineKind, SalesOrderStatus } from "@/lib/graphql/generated";
import { isCancellationEvent, pendingLineText, PURCHASE_ORDER_TIMELINE_LABEL, totalAmountText } from "./format";
import { PURCHASE_ORDER_STATUS, SALES_ORDER_STATUS } from "./statuses";

// codegen の型は値の一覧を持たないので、型がすべての値を鍵に求める状況の一覧から集める
const SALES_ORDER_STATUSES = Object.keys(SALES_ORDER_STATUS) as SalesOrderStatus[];
const PURCHASE_ORDER_STATUSES = Object.keys(PURCHASE_ORDER_STATUS) as PurchaseOrderStatus[];

// 照合待ち・確定待ちのまま取り消した伝票は、合計の欄に「取消」と出す (docs/architecture/context-map.md「発注の連結と品番の照合」)。
// 受注側の取消も発注側の取消も含む
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

// 照合待ち・確定待ちのまま取り消した伝票は、明細の行にも待ちの文言の代わりに取消の文言を出す。もう何も待たないので
describe("pendingLineText", () => {
  it("取り消した受注の明細は「品番未照合（取消）」、ほかの受注の明細は「品番照合待ち」を出す", () => {
    expect(pendingLineText("salesOrder", "CANCELLED")).toBe("品番未照合（取消）");
    for (const status of SALES_ORDER_STATUSES) {
      expect(pendingLineText("salesOrder", status), status).toBe(
        CANCELLED_SALES_ORDER.includes(status) ? "品番未照合（取消）" : "品番照合待ち",
      );
    }
  });

  it("取り消した発注の明細は「未確定（取消）」、ほかの発注の明細は「受注側の確定待ち」を出す", () => {
    for (const status of PURCHASE_ORDER_STATUSES) {
      expect(pendingLineText("purchaseOrder", status), status).toBe(
        CANCELLED_PURCHASE_ORDER.includes(status) ? "未確定（取消）" : "受注側の確定待ち",
      );
    }
  });
});

describe("isCancellationEvent", () => {
  // 取消の回答と受注側の取消は、取り消した伝票の明細の文言と同じ控えめの色で出す。取消依頼はまだ取り消していないので含めない
  const CANCELLATION: readonly PurchaseOrderTimelineKind[] = ["CANCELLATION_APPROVED", "CANCELLATION_REJECTED", "SUPPLIER_CANCELLED"];

  it("取消の承認・却下と受注側の取消だけを取消の出来事にする", () => {
    for (const kind of Object.keys(PURCHASE_ORDER_TIMELINE_LABEL) as PurchaseOrderTimelineKind[]) {
      expect(isCancellationEvent(kind), kind).toBe(CANCELLATION.includes(kind));
    }
    // 対照：取消の出来事の一覧の値は、すべて出来事の種類にある
    expect(CANCELLATION.every((kind) => kind in PURCHASE_ORDER_TIMELINE_LABEL)).toBe(true);
  });
});
