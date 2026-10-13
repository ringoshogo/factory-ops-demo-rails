import { describe, expect, it } from "vitest";

import { isIsoDate, monthGrid, moveDate, withMonth } from "./calendar";

describe("monthGrid: 6 週 × 7 日、日曜始まり、月の外は null", () => {
  it("2026年10月(1日が木曜): 1 週目は日〜水が null、1日が木曜の列", () => {
    const grid = monthGrid(2026, 10);
    expect(grid).toHaveLength(6);
    for (const week of grid) expect(week).toHaveLength(7);
    expect(grid[0]).toEqual([null, null, null, null, "2026-10-01", "2026-10-02", "2026-10-03"]);
    expect(grid[1][0]).toBe("2026-10-04");
    // 31日は土曜。5 週目の末尾
    expect(grid[4]).toEqual([
      "2026-10-25",
      "2026-10-26",
      "2026-10-27",
      "2026-10-28",
      "2026-10-29",
      "2026-10-30",
      "2026-10-31",
    ]);
    expect(grid[5]).toEqual([null, null, null, null, null, null, null]);
  });

  it("月の日がすべて 1 回ずつ、順に並ぶ", () => {
    const days = monthGrid(2026, 10)
      .flat()
      .filter((d): d is string => d !== null);
    const expected = Array.from({ length: 31 }, (_, i) => `2026-10-${String(i + 1).padStart(2, "0")}`);
    expect(days).toEqual(expected);
  });

  it("月初が日曜の月は 1 週目の日曜から始まる(空の週を前に置かない)", () => {
    const grid = monthGrid(2026, 2); // 2026-02-01 は日曜、28 日で 4 週ちょうど
    expect(grid).toHaveLength(6);
    expect(grid[0]).toEqual([
      "2026-02-01",
      "2026-02-02",
      "2026-02-03",
      "2026-02-04",
      "2026-02-05",
      "2026-02-06",
      "2026-02-07",
    ]);
    expect(grid[3][6]).toBe("2026-02-28");
    expect(grid[4]).toEqual([null, null, null, null, null, null, null]);
    expect(grid[5]).toEqual([null, null, null, null, null, null, null]);
  });

  it("6 週を使い切る月(2026年8月: 1日が土曜・31日)", () => {
    const grid = monthGrid(2026, 8);
    expect(grid[0]).toEqual([null, null, null, null, null, null, "2026-08-01"]);
    expect(grid[5]).toEqual(["2026-08-30", "2026-08-31", null, null, null, null, null]);
  });

  it("閏年の2月は29日まで", () => {
    const days = monthGrid(2024, 2).flat().filter((d) => d !== null);
    expect(days).toHaveLength(29);
    expect(days.at(-1)).toBe("2024-02-29");
  });
});

describe("moveDate: キーごとの移動", () => {
  const D = "2026-10-08"; // 木曜

  it("←→ は 1 日、↑↓ は 1 週", () => {
    expect(moveDate(D, "ArrowLeft")).toBe("2026-10-07");
    expect(moveDate(D, "ArrowRight")).toBe("2026-10-09");
    expect(moveDate(D, "ArrowUp")).toBe("2026-10-01");
    expect(moveDate(D, "ArrowDown")).toBe("2026-10-15");
  });

  it("月・年をまたぐ", () => {
    expect(moveDate("2026-10-01", "ArrowLeft")).toBe("2026-09-30");
    expect(moveDate("2026-12-31", "ArrowRight")).toBe("2027-01-01");
    expect(moveDate("2026-10-03", "ArrowUp")).toBe("2026-09-26");
    expect(moveDate("2026-12-28", "ArrowDown")).toBe("2027-01-04");
  });

  it("Home・End はその週の日曜・土曜", () => {
    expect(moveDate(D, "Home")).toBe("2026-10-04");
    expect(moveDate(D, "End")).toBe("2026-10-10");
    // 週が月をまたぐ
    expect(moveDate("2026-10-01", "Home")).toBe("2026-09-27");
    expect(moveDate("2026-09-30", "End")).toBe("2026-10-03");
    // 既に日曜・土曜ならそのまま
    expect(moveDate("2026-10-04", "Home")).toBe("2026-10-04");
    expect(moveDate("2026-10-10", "End")).toBe("2026-10-10");
  });

  it("PageUp・PageDown は前後の月、Shift 付きは前後の年", () => {
    expect(moveDate(D, "PageUp")).toBe("2026-09-08");
    expect(moveDate(D, "PageDown")).toBe("2026-11-08");
    expect(moveDate(D, "Shift+PageUp")).toBe("2025-10-08");
    expect(moveDate(D, "Shift+PageDown")).toBe("2027-10-08");
    expect(moveDate("2026-01-15", "PageUp")).toBe("2025-12-15");
    expect(moveDate("2026-12-15", "PageDown")).toBe("2027-01-15");
  });

  it("月末を丸める(1月31日 → 2月28日、閏年は 29日)", () => {
    expect(moveDate("2026-01-31", "PageDown")).toBe("2026-02-28");
    expect(moveDate("2024-01-31", "PageDown")).toBe("2024-02-29");
    expect(moveDate("2026-03-31", "PageUp")).toBe("2026-02-28");
    expect(moveDate("2026-10-31", "PageDown")).toBe("2026-11-30");
    expect(moveDate("2024-02-29", "Shift+PageDown")).toBe("2025-02-28");
    expect(moveDate("2024-02-29", "Shift+PageUp")).toBe("2023-02-28");
  });
});

describe("0001〜0099 年も年を保って計算する (Date.UTC の 1900 年補正を受けない)", () => {
  it("0099年から0100年へ動く", () => {
    expect(moveDate("0099-12-31", "ArrowRight")).toBe("0100-01-01");
    expect(moveDate("0100-01-01", "ArrowLeft")).toBe("0099-12-31");
    expect(moveDate("0099-12-31", "PageDown")).toBe("0100-01-31");
    expect(moveDate("0004-02-29", "Shift+PageDown")).toBe("0005-02-28");
  });

  it("初期の年の曜日 (Home・End) と格子", () => {
    // 0099-12-31 は木曜
    expect(moveDate("0099-12-31", "Home")).toBe("0099-12-27");
    expect(moveDate("0099-12-31", "End")).toBe("0100-01-02");
    expect(monthGrid(99, 12)[4]).toEqual(["0099-12-27", "0099-12-28", "0099-12-29", "0099-12-30", "0099-12-31", null, null]);
  });

  it("初期の年の閏日", () => {
    expect(monthGrid(4, 2).flat().filter((d) => d !== null)).toHaveLength(29);
    expect(isIsoDate("0004-02-29")).toBe(true);
    expect(isIsoDate("0100-02-29")).toBe(false);
    expect(isIsoDate("0099-02-29")).toBe(false);
  });
});

describe("isIsoDate: 実在する YYYY-MM-DD か", () => {
  it("実在する日は受け入れる", () => {
    expect(isIsoDate("2026-10-08")).toBe(true);
    expect(isIsoDate("2024-02-29")).toBe(true);
    expect(isIsoDate("2026-12-31")).toBe(true);
  });

  it("実在しない日を拒む", () => {
    expect(isIsoDate("2026-02-30")).toBe(false);
    expect(isIsoDate("2026-02-29")).toBe(false);
    expect(isIsoDate("2026-13-01")).toBe(false);
    expect(isIsoDate("2026-00-10")).toBe(false);
    expect(isIsoDate("2026-04-31")).toBe(false);
    expect(isIsoDate("2026-10-00")).toBe(false);
  });

  it("形の違う文字列を拒む", () => {
    for (const raw of ["", "2026-1-8", "2026/10/08", "20261008", "2026-10-08T00:00:00Z", " 2026-10-08", "abcd-ef-gh"]) {
      expect(isIsoDate(raw), raw).toBe(false);
    }
  });
});

describe("withMonth: 年・月の選択欄で表示する月を替える (日は保ち、無ければ月末に丸める)", () => {
  it("日を保つ", () => {
    expect(withMonth("2026-10-08", 2030, 12)).toBe("2030-12-08");
    expect(withMonth("2026-10-08", 2026, 1)).toBe("2026-01-08");
  });
  it("移動先の月に無い日は月末に丸める (閏年を区別する)", () => {
    expect(withMonth("2026-01-31", 2026, 2)).toBe("2026-02-28");
    expect(withMonth("2026-01-31", 2028, 2)).toBe("2028-02-29");
    expect(withMonth("2026-03-31", 2026, 4)).toBe("2026-04-30");
  });
});
