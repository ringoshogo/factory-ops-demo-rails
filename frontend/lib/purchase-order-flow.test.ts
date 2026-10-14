import { describe, expect, it } from "vitest";

import type { PurchaseOrderStatus } from "@/lib/graphql/generated";
import { canRequestCancellation } from "./purchase-order-flow";
import { PURCHASE_ORDER_STATUS } from "./statuses";

// codegen の型は値の一覧を持たないので、型がすべての値を鍵に求める状況の一覧から集める。API が値を足すと、ここにも入る
const ALL = Object.keys(PURCHASE_ORDER_STATUS) as PurchaseOrderStatus[];

// 取消依頼は出荷の前だけ (docs/architecture/context-map.md「取消の流れ」)。出荷済の受注への依頼は受注側が必ず却下するので、
// 却下だけが返る操作を見せない
const BEFORE_SHIPMENT: readonly PurchaseOrderStatus[] = ["SENT", "AWAITING_SUPPLIER_CONFIRMATION", "ACCEPTED"];

describe("canRequestCancellation: 発注詳細の取消依頼のボタン", () => {
  it("出荷の前の発注にだけ出し、入荷予定・検収済・取消済みには出さない", () => {
    expect(canRequestCancellation({ status: "INBOUND", cancellationPending: false })).toBe(false);
    for (const status of ALL) {
      expect(canRequestCancellation({ status, cancellationPending: false }), status).toBe(BEFORE_SHIPMENT.includes(status));
    }
    // 空振りしない：出す状況も出さない状況も、すべての値の中にある
    expect(ALL.filter((s) => BEFORE_SHIPMENT.includes(s))).toHaveLength(BEFORE_SHIPMENT.length);
    expect(ALL.length).toBeGreaterThan(BEFORE_SHIPMENT.length);
  });

  it("回答を待つ依頼がある発注には、出荷の前でも出さない", () => {
    expect(canRequestCancellation({ status: "ACCEPTED", cancellationPending: false })).toBe(true);
    expect(canRequestCancellation({ status: "ACCEPTED", cancellationPending: true })).toBe(false);
  });
});
