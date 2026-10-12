import { describe, expect, it } from "vitest";

import { INT_MAX, INT_MIN, parseInt32, parseIntegerText } from "./form-input";

describe("parseInt32: GraphQL の Int に送れる整数", () => {
  it("Int の上限ちょうどと下限ちょうどは受け、1 つ外は受けない", () => {
    expect(parseInt32("2147483647")).toBe(2147483647);
    expect(parseInt32("-2147483648")).toBe(-2147483648);
    expect(parseInt32("2147483648")).toBeNull();
    expect(parseInt32("-2147483649")).toBeNull();
    expect(INT_MAX).toBe(2147483647);
    expect(INT_MIN).toBe(-2147483648);
  });

  it("前後の空白は除き、数でない値・小数・空は受けない", () => {
    expect(parseInt32(" 12 ")).toBe(12);
    expect(parseInt32("1.5")).toBeNull();
    expect(parseInt32("abc")).toBeNull();
    expect(parseInt32("")).toBeNull();
  });
});

describe("parseIntegerText: BigInt に送る金額", () => {
  it("整数の形なら Int の範囲を超えても文字列のまま返す", () => {
    expect(parseIntegerText("99999999999")).toBe("99999999999");
    expect(parseIntegerText("12a")).toBeNull();
  });
});
