import { describe, expect, it } from "vitest";
import { totalAmountText } from "./format";

describe("totalAmountText", () => {
  it("合計があれば 3 桁区切りの円で出し、2^53 を超える値も丸めない", () => {
    expect(totalAmountText("1050", "salesOrder")).toBe("1,050 円");
    expect(totalAmountText("27670116110564327421", "purchaseOrder")).toBe("27,670,116,110,564,327,421 円");
  });

  it("合計が空なら 0 円にせず、受注は「照合待ち」、発注は「確定待ち」を出す", () => {
    expect(totalAmountText(null, "salesOrder")).toBe("照合待ち");
    expect(totalAmountText(null, "purchaseOrder")).toBe("確定待ち");
    // 対照：0 円の合計は空と区別して金額で出す
    expect(totalAmountText("0", "salesOrder")).toBe("0 円");
  });
});
