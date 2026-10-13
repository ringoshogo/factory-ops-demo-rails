import { describe, expect, it } from "vitest";

import type { SalesOrderStatus, ShipmentRequestStatus } from "@/lib/graphql/generated";
import { canCancel, canCancelInstruction, nextAction, orderMark } from "./sales-order-flow";

const order = (status: SalesOrderStatus, request: ShipmentRequestStatus | null = null, pending = false) => ({
  status,
  shipmentRequest: request ? { status: request } : null,
  cancellationReviewPending: pending,
});

describe("nextAction: かんばんのカードの次の操作", () => {
  it("受注済と一部引当は引当、引当済は出荷依頼の状況で出荷指示か出荷実績の計上", () => {
    expect(nextAction(order("RECEIVED"))).toBe("allocate");
    expect(nextAction(order("PARTIALLY_ALLOCATED"))).toBe("allocate");
    expect(nextAction(order("ALLOCATED", "READY"))).toBe("instruct");
    expect(nextAction(order("ALLOCATED", "INSTRUCTED"))).toBe("ship");
  });

  it("品番照合待ち・出荷停止中・出荷済・検収済・取消済は操作を置かない", () => {
    expect(nextAction(order("AWAITING_PART_MATCH"))).toBeNull();
    expect(nextAction(order("ALLOCATED", "ON_HOLD"))).toBeNull();
    expect(nextAction(order("SHIPPED", "SHIPPED"))).toBeNull();
    expect(nextAction(order("INSPECTED", "SHIPPED"))).toBeNull();
    expect(nextAction(order("CANCELLED", "CANCELLED"))).toBeNull();
  });
});

describe("取消と出荷指示の取消", () => {
  it("出荷・検収・取消の前の受注だけを取り消せる", () => {
    expect(canCancel(order("AWAITING_PART_MATCH"))).toBe(true);
    expect(canCancel(order("ALLOCATED", "INSTRUCTED"))).toBe(true);
    expect(canCancel(order("SHIPPED"))).toBe(false);
    expect(canCancel(order("INSPECTED"))).toBe(false);
    expect(canCancel(order("CANCELLED"))).toBe(false);
  });

  it("出荷指示の取消は出荷指示済のときだけ", () => {
    expect(canCancelInstruction(order("ALLOCATED", "INSTRUCTED"))).toBe(true);
    expect(canCancelInstruction(order("ALLOCATED", "READY"))).toBe(false);
  });
});

describe("orderMark: 状況のバッジに重ねる印", () => {
  it("取消審査中を先に出し、引当済の受注には出荷指示済と出荷停止中を出す", () => {
    expect(orderMark(order("ALLOCATED", "ON_HOLD", true))).toBe("取消審査中");
    expect(orderMark(order("ALLOCATED", "INSTRUCTED"))).toBe("出荷指示済");
    expect(orderMark(order("ALLOCATED", "ON_HOLD"))).toBe("出荷停止中");
    expect(orderMark(order("ALLOCATED", "READY"))).toBeUndefined();
    expect(orderMark(order("SHIPPED", "SHIPPED"))).toBeUndefined();
  });
});
