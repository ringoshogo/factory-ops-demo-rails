import { describe, expect, it } from "vitest";

import { commentsOf, RULES, violations } from "./check-comments.mjs";

const hits = (comment) => violations(comment);

describe("violations: コメントの規約に当たる語", () => {
  const cases = [
    ["マイルストーンの番号", "// 出荷停止中は M15 で足す", "// 六角穴付きボルト M8x30 の品番"],
    ["マイルストーンの番号", "// 和文に挟まった停止中はM15で足す", "// M2M の連携"],
    ["台帳の ID", "// 上限ちょうども書く (OI-25)", "// OI-ring の型番"],
    ["台帳の ID", "// IB-3 の候補", "// LIB-3 の部品"],
    ["流用元のタスクの番号", "// 実測で決めた (T-34a)", "// T-shirt の色"],
    ["流用元の正本の番号", "// 先読みしない (N-15)", "// N-type の端子"],
    ["流用元の正本の番号", "// 正本 US-10", "// US の祝日"],
    ["流用元の仕様の節", "// 見た目は仕様 cycle-03 §2 の表", "// 仕様どおりに並べる"],
    ["流用元の仕様の節", "// §3 外枠", "// § だけの記号"],
    ["流用元の正本・台帳への参照", "// 正本 N-4", "// 正本へ戻す"],
    ["経緯の語", "// レビューで直した", "// 読み込み直した値"],
    ["経緯の語", "// 以前は全件を読んだ", "// 以前の値と比べる"],
    ["予定", "// TODO: あとで直す", "// TODOS の一覧"],
  ];

  it.each(cases)("%s: 当たる例は止め、英数字の続きや別の語は止めない", (name, bad, good) => {
    expect(hits(bad)).toContain(name);
    expect(hits(good)).not.toContain(name);
  });

  it("どの規則にも当たる例と当たらない例がある (規則を外すと上の表の例が落ちる)", () => {
    const covered = new Set(cases.map(([name]) => name));
    expect(RULES.map((rule) => rule.name).filter((name) => !covered.has(name))).toEqual([]);
  });
});

describe("commentsOf: ファイルの種類ごとにコメントだけを取り出す", () => {
  it("TypeScript は行コメントと塊のコメントを取り、文字列の中の語は拾わない", () => {
    const text = 'const s = "M15 OI-1"; // コメント M15\n/* 塊 */\nconst t = `${s} // M16`;\n// テンプレートの後 M17\n';
    const found = commentsOf("a.ts", text);
    expect(found.map(([, c]) => c)).toEqual(["// コメント M15", "/* 塊 */", "// テンプレートの後 M17"]);
    expect(found.map(([line]) => line)).toEqual([1, 2, 4]);
  });

  it("TSX は JSX の中の {/* */} を取り、JSX の文字は拾わない", () => {
    const text = 'export const A = () => (\n  <p>\n    {/* JSX の中 M1 */}\n    // 文字 M2\n  </p>\n);\n';
    expect(commentsOf("a.tsx", text).map(([, c]) => c)).toEqual(["/* JSX の中 M1 */"]);
  });

  it("CSS は塊のコメント、GraphQL は # のコメントを取る", () => {
    expect(commentsOf("a.css", "a { color: red; } /* 色 M1 */").map(([, c]) => c)).toEqual(["/* 色 M1 */"]);
    expect(commentsOf("a.graphql", "query A { # 説明 M1\n  b\n}").map(([, c]) => c)).toEqual(["# 説明 M1"]);
  });

  it("対象でない種類のファイルは見ない", () => {
    expect(commentsOf("a.json", '{"a": "// M1"}')).toEqual([]);
  });
});
