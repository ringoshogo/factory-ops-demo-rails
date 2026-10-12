import { afterEach, describe, expect, it, vi } from "vitest";

import {
  dateRangeLabel,
  daysUntil,
  dueNote,
  formatBusinessDate,
  formatDate,
  formatDateTime,
  formatFullDate,
  isOverdue,
  todayInTokyo,
} from "./dates";

// 未完了か (出荷も取消もしていない) と期限の組。画面は状況から未完了かを決めて渡す
const OPEN = true;
const DONE = false;

describe("formatDate: 一覧・詳細の日付", () => {
  it("業務日付と同じ年なら年を付けない", () => {
    expect(formatDate("2026-10-08", "2026-10-07")).toBe("10月8日");
    expect(formatDate("2026-01-05", "2026-12-31")).toBe("1月5日");
  });

  it("業務日付と年が違えば年を付ける", () => {
    expect(formatDate("2025-12-26", "2026-01-15")).toBe("2025年12月26日");
    expect(formatDate("2027-01-02", "2026-12-31")).toBe("2027年1月2日");
  });

  it("業務日付が分からなければ年を付ける", () => {
    expect(formatDate("2026-10-08", null)).toBe("2026年10月8日");
  });
});

describe("formatDateTime: 在庫移動履歴の日時 (Asia/Tokyo)", () => {
  it("UTC の時刻を東京の時刻で出し、同じ年なら年を付けない", () => {
    expect(formatDateTime("2026-10-08T05:32:00Z", "2026-10-07")).toBe("10月8日 14:32");
  });

  it("東京で日付と年が変わる時刻は、東京の年で業務日付と比べる", () => {
    // UTC では 2025-12-31、東京では 2026-01-01 00:30
    expect(formatDateTime("2025-12-31T15:30:00Z", "2026-01-15")).toBe("1月1日 00:30");
    expect(formatDateTime("2025-12-31T14:30:00Z", "2026-01-15")).toBe("2025年12月31日 23:30");
  });

  it("業務日付が分からなければ年を付ける", () => {
    expect(formatDateTime("2026-01-15T09:01:00Z", null)).toBe("2026年1月15日 18:01");
  });
});

describe("formatBusinessDate: ダッシュボードの業務日付", () => {
  it("年月日と曜日を付ける", () => {
    expect(formatBusinessDate("2026-10-07")).toBe("2026年10月7日(水)");
    expect(formatBusinessDate("2026-01-15")).toBe("2026年1月15日(木)");
    expect(formatBusinessDate("2026-02-01")).toBe("2026年2月1日(日)");
    expect(formatBusinessDate("2026-10-10")).toBe("2026年10月10日(土)");
  });
});

describe("formatFullDate: 日付ボタンの表示", () => {
  it("年を常に付ける", () => {
    expect(formatFullDate("2026-10-08")).toBe("2026年10月8日");
    expect(formatFullDate("2025-12-26")).toBe("2025年12月26日");
  });
});

describe("daysUntil: UTC の日として差を数える", () => {
  it("後なら正、前なら負、同じ日なら 0", () => {
    expect(daysUntil("2026-10-07", "2026-10-10")).toBe(3);
    expect(daysUntil("2026-10-07", "2026-10-06")).toBe(-1);
    expect(daysUntil("2026-10-07", "2026-10-07")).toBe(0);
  });

  it("月・年・閏日をまたぐ", () => {
    expect(daysUntil("2026-12-31", "2027-01-01")).toBe(1);
    expect(daysUntil("2024-02-28", "2024-03-01")).toBe(2);
    expect(daysUntil("2025-02-28", "2025-03-01")).toBe(1);
  });
});

describe("0001〜0099 年も年を保って計算する (Date.UTC の 1900 年補正を受けない)", () => {
  it("daysUntil が 0099年と0100年の間を 1 日と数える", () => {
    expect(daysUntil("0099-12-31", "0100-01-01")).toBe(1);
    expect(daysUntil("0004-02-28", "0004-03-01")).toBe(2);
  });

  it("formatBusinessDate の曜日", () => {
    expect(formatBusinessDate("0099-12-31")).toBe("99年12月31日(木)");
    expect(formatBusinessDate("0004-02-29")).toBe("4年2月29日(日)");
  });
});

describe("isOverdue: 期限の超過を決める 1 か所の判定", () => {
  it("未完了で期限が業務の今日より前なら超過", () => {
    expect(isOverdue("2026-10-06", OPEN, "2026-10-07")).toBe(true);
  });

  it("期限が業務の今日と同じなら超過ではない", () => {
    expect(isOverdue("2026-10-07", OPEN, "2026-10-07")).toBe(false);
  });

  it("完了した伝票は期限を過ぎていても超過ではない", () => {
    expect(isOverdue("2026-01-01", DONE, "2026-10-07")).toBe(false);
  });
});

describe("dueNote: 未完了の伝票の期限に添える文言", () => {
  const BIZ = "2026-10-07";

  it("差で文言が変わる (−1・0・1・2・3 日)", () => {
    expect(dueNote("2026-10-06", OPEN, BIZ)).toEqual({ label: "期限超過", overdue: true });
    expect(dueNote("2026-10-07", OPEN, BIZ)).toEqual({ label: "今日", overdue: false });
    expect(dueNote("2026-10-08", OPEN, BIZ)).toEqual({ label: "明日", overdue: false });
    expect(dueNote("2026-10-09", OPEN, BIZ)).toEqual({ label: "あと2日", overdue: false });
    expect(dueNote("2026-10-10", OPEN, BIZ)).toEqual({ label: "あと3日", overdue: false });
  });

  it("4 日以上先は文言を付けない (3 と 4 の境界)", () => {
    expect(dueNote("2026-10-10", OPEN, BIZ)).not.toBeNull();
    expect(dueNote("2026-10-11", OPEN, BIZ)).toBeNull();
    expect(dueNote("2026-12-31", OPEN, BIZ)).toBeNull();
  });

  it("大きく過ぎていても期限超過", () => {
    expect(dueNote("2025-12-26", OPEN, BIZ)).toEqual({ label: "期限超過", overdue: true });
  });

  it("完了した伝票には付けない (期限が近くても・過ぎていても)", () => {
    for (const due of ["2026-10-06", "2026-10-07", "2026-10-08"]) {
      expect(dueNote(due, DONE, BIZ)).toBeNull();
    }
  });

  it("業務の今日が分からなければ付けない", () => {
    expect(dueNote("2026-10-06", OPEN, null)).toBeNull();
    expect(dueNote("2026-10-07", OPEN, null)).toBeNull();
  });

  it("期限の超過の判定は isOverdue と一致する (未完了と完了 × 前後の日)", () => {
    const dues = ["2025-12-31", "2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-11"];
    let overdueSeen = 0;
    for (const open of [OPEN, DONE]) {
      for (const due of dues) {
        const expected = isOverdue(due, open, BIZ);
        if (expected) overdueSeen++;
        expect(dueNote(due, open, BIZ)?.overdue ?? false, `${open} ${due}`).toBe(expected);
        expect(dueNote(due, open, BIZ)?.label === "期限超過", `${open} ${due}`).toBe(expected);
      }
    }
    // 空振りしない: 超過の組が実際に含まれる (未完了 × 過去 3 日)
    expect(overdueSeen).toBe(3);
  });
});

describe("dateRangeLabel: 受注日の期間のボタンの値", () => {
  it("両方なら「開始〜終了」", () => {
    expect(dateRangeLabel("2026-10-01", "2026-10-08", "2026-10-07")).toBe("10月1日〜10月8日");
  });

  it("片側なら「以降」「以前」", () => {
    expect(dateRangeLabel("2026-10-01", "", "2026-10-07")).toBe("10月1日以降");
    expect(dateRangeLabel("", "2026-10-08", "2026-10-07")).toBe("10月8日以前");
  });

  it("無ければ「期間を選ぶ」", () => {
    expect(dateRangeLabel("", "", "2026-10-07")).toBe("期間を選ぶ");
  });

  it("年の付け方は formatDate と同じ (業務日付と違う年・業務日付が無い)", () => {
    expect(dateRangeLabel("2025-12-26", "2026-01-05", "2026-01-15")).toBe("2025年12月26日〜1月5日");
    expect(dateRangeLabel("2026-10-01", "", null)).toBe("2026年10月1日以降");
  });
});

describe("todayInTokyo: 業務日付が得られないときの基準の日 (Asia/Tokyo の今日)", () => {
  afterEach(() => vi.useRealTimers());
  it("UTC で前日の 15:00 以降は東京の翌日", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-07T15:30:00Z"));
    expect(todayInTokyo()).toBe("2026-10-08");
    vi.setSystemTime(new Date("2026-10-07T14:59:00Z"));
    expect(todayInTokyo()).toBe("2026-10-07");
  });
});

describe("dateRangeLabel: URL の不正な値 (形式違い・実在しない日) は NaN にせず、そのまま出す", () => {
  it.each([
    ["abc", "", "abc以降"],
    ["2026-02-30", "", "2026-02-30以降"],
    ["", "abc", "abc以前"],
    ["", "2026-02-30", "2026-02-30以前"],
    ["2026-01-10", "abc", "1月10日〜abc"],
    ["2026-02-30", "2026-03-01", "2026-02-30〜3月1日"],
  ])("from=%s to=%s → %s", (from, to, expected) => {
    const label = dateRangeLabel(from, to, "2026-01-15");
    expect(label).not.toMatch(/NaN|undefined/);
    expect(label).toBe(expected);
  });
});
