import { expect, type Page } from "@playwright/test";

/**
 * 表の列のそろえ。
 *
 * - 数値の列だけ見出しもセルも右寄せ。ほかの列 (操作を含む) は左寄せ
 * - 見出しの**文字**とセルの中身の端が 1px 以内でそろう (左寄せの列は左端、右寄せの列は右端)
 * - ソートの矢印はどの列も文字の右
 * - 1280・1024 で表がパネル (main) に収まる (表の容器が横にスクロールしない)
 * - 長い文字の列は折り返さず、収まらなければ末尾を省略する。全文は title とアクセシブル名で読める
 * - 1024 では行の高さが表の中でそろう (複数の明細を行の中に並べる表は除く)
 *
 * 文字の端は Range で測る (見出しのボタンの矢印を含めない)。セルは文字と、行の中に置かれた箱
 * (ボタン・バッジ) の外接矩形で測る (操作の並びのようなブロックの容器はセルの幅いっぱいなので数えない)。
 */

/**
 * 画面ごとの表と、その数値の列・省略できる文字の列 (見出しの文字)。列の一覧はここだけに置く。
 * 利用者が入れる文字 (コード・名前・単位・住所・担当者名・品目・理由) は長さの上限が無いので、すべて省略できる列にする。
 */
export const TABLE_SCREENS: { path: string; numeric: string[]; truncate: string[] }[] = [
  { path: "/dashboard", numeric: ["有効在庫", "安全在庫", "不足"], truncate: ["品目コード", "品名"] },
  { path: "/orders", numeric: ["受注合計"], truncate: ["得意先"] },
  { path: "/stocks", numeric: ["現在庫", "引当済", "有効在庫", "安全在庫"], truncate: ["品目コード", "品名"] },
  { path: "/stocks?tab=movements", numeric: ["数量"], truncate: ["品目", "理由"] },
  { path: "/shipping-instructions", numeric: [], truncate: ["得意先", "品目・数量"] },
  { path: "/items", numeric: ["販売単価", "安全在庫数"], truncate: ["品目コード", "品名", "単位"] },
  { path: "/customers", numeric: [], truncate: ["得意先コード", "得意先名", "住所", "担当者名"] },
];

/** 1280・1024 は表がパネルに収まる。390 は表の容器の中で横にスクロールしてよい 。 */
export const FIT_WIDTHS = [1280, 1024];

const TOLERANCE = 1;

type Edge = { left: number; right: number };
type Column = {
  head: string;
  headAlign: string;
  label: Edge;
  /** ソートの矢印。ソートできない見出しは null */
  icon: Edge | null;
  cells: {
    align: string;
    content: Edge | null;
    buttons: { top: number; bottom: number }[];
    cell: { top: number; bottom: number };
    /** 省略できる文字 (title を持つ要素) ごとの title・全文・省略されているか */
    texts: { title: string | null; full: string; clipped: boolean }[];
  }[];
};
type Measured = {
  columns: Column[];
  /** データ行の高さと、出荷指示の明細の数 (複数明細の行は高さの比較から外す) */
  rows: { height: number; lines: number }[];
  containers: { scroll: number; client: number }[];
  table: number;
  main: number;
};

async function measure(page: Page): Promise<Measured[]> {
  return page.evaluate(() => {
    const box = (r: DOMRect) => ({ left: r.left, right: r.right });
    // 中身の端: 文字のノードと、行の中に置かれた箱 (ボタン・バッジ・アイコン等の inline-block / inline-flex) の外接矩形。
    // ブロックや flex の容器 (操作の並び等) はセルの幅いっぱいに広がるので、箱としては数えず中を見る
    const ATOMIC = new Set(["inline-block", "inline-flex", "inline-grid", "inline-table"]);
    const leafRects = (node: Node): DOMRect[] => {
      if (node.nodeType === Node.TEXT_NODE) {
        const range = document.createRange();
        range.selectNodeContents(node);
        return [...range.getClientRects()];
      }
      if (!(node instanceof Element)) return [];
      if (node instanceof SVGElement || node.matches("button, input, img") || ATOMIC.has(getComputedStyle(node).display)) {
        return [node.getBoundingClientRect()];
      }
      return [...node.childNodes].flatMap(leafRects);
    };
    const textEdge = (nodes: Node[]) => {
      const rects = nodes.flatMap((n) => (n instanceof Element ? [...n.childNodes].flatMap(leafRects) : leafRects(n))).filter((r) => r.width > 0);
      if (rects.length === 0) return null;
      return { left: Math.min(...rects.map((r) => r.left)), right: Math.max(...rects.map((r) => r.right)) };
    };
    const main = document.querySelector("main")!;
    const mainStyle = getComputedStyle(main);
    const mainWidth = main.clientWidth - parseFloat(mainStyle.paddingLeft) - parseFloat(mainStyle.paddingRight);
    return [...document.querySelectorAll("main table")].map((table) => {
      const heads = [...table.querySelectorAll("thead th")] as HTMLElement[];
      const rows = [...table.querySelectorAll("tbody tr")].filter((tr) => tr.children.length === heads.length);
      const columns = heads.map((th, i) => {
        const button = th.querySelector("button");
        // 見出しの文字: ボタンなら中の文字のノードだけ (矢印の svg を含めない)
        const labelNodes = button
          ? [...button.childNodes].filter((n) => n.nodeType === Node.TEXT_NODE)
          : [th];
        const svg = th.querySelector("svg");
        return {
          head: th.textContent ?? "",
          headAlign: getComputedStyle(th).textAlign,
          label: textEdge(labelNodes)!,
          icon: svg ? box(svg.getBoundingClientRect()) : null,
          cells: rows.map((tr) => {
            const td = tr.children[i] as HTMLElement;
            const r = td.getBoundingClientRect();
            return {
              align: getComputedStyle(td).textAlign,
              content: textEdge([td]),
              // 表示されているボタンだけ (幅で出し分けて隠れている方は数えない)
              buttons: [...td.querySelectorAll("button")]
                .map((b) => b.getBoundingClientRect())
                .filter((br) => br.width > 0)
                .map((br) => ({ top: br.top, bottom: br.bottom })),
              texts: [...td.querySelectorAll("[data-truncate]")].map((el) => ({
                title: el.getAttribute("title"),
                full: (el.textContent ?? "").trim(),
                clipped: el.scrollHeight > el.clientHeight + 1 || el.scrollWidth > el.clientWidth + 1,
              })),
              cell: { top: r.top, bottom: r.bottom },
            };
          }),
        };
      });
      // 表を囲む横スクロールの容器 (表の部品の容器と、画面側の容器の両方)
      const containers: { scroll: number; client: number }[] = [];
      for (let el = table.parentElement; el && el !== main; el = el.parentElement) {
        const ox = getComputedStyle(el).overflowX;
        if (ox === "auto" || ox === "scroll") containers.push({ scroll: el.scrollWidth, client: el.clientWidth });
      }
      const rowBoxes = rows.map((tr) => ({
        height: Math.round(tr.getBoundingClientRect().height * 10) / 10,
        lines: tr.querySelectorAll('[data-testid="instruction-line"]').length,
      }));
      return { columns, rows: rowBoxes, containers, table: table.getBoundingClientRect().width, main: mainWidth };
    });
  });
}

const isRight = (align: string) => align === "right" || align === "end";

/**
 * 今の画面の全部の表について、そろえ・省略・行の高さ・はみ出しを検査する。失敗はまとめて出す (expect.soft)。
 * `fit` が真なら、表がパネルに収まり、行の高さがそろうことも見る。省略された文字の列 (画面「列」) を返す。
 */
export async function expectTablesAligned(
  page: Page,
  { path, numeric, truncate }: { path: string; numeric: string[]; truncate: string[] },
  fit: boolean,
): Promise<string[]> {
  const clipped: string[] = [];
  await expect(page.locator("main tbody tr").first()).toBeVisible();
  // 文字の幅で列の幅が変わるので、Web フォントの読み込みを待ってから測る
  await page.evaluate(() => document.fonts.ready);
  const tables = await measure(page);
  expect(tables.length, `${path}: 表がある`).toBeGreaterThan(0);
  const seenNumeric = new Set<string>();

  for (const [t, table] of tables.entries()) {
    const name = `${path} の表 ${t + 1}`;
    expect(table.columns[0].cells.length, `${name}: データ行がある`).toBeGreaterThan(0);
    for (const [ci, col] of table.columns.entries()) {
      const label = col.head.trim();
      const num = numeric.includes(label);
      // 長い文字の列: 中身のあるセルは、全文を title に持つ省略の要素を持つ。読み上げも全文
      if (truncate.includes(label)) {
        for (const [r, cell] of col.cells.entries()) {
          if (!cell.content) continue;
          expect.soft(cell.texts.length, `${name}「${label}」${r + 1} 行目: 省略できる文字の要素がある`).toBeGreaterThan(0);
          for (const x of cell.texts) {
            expect.soft(x.title, `${name}「${label}」${r + 1} 行目: title が全文`).toBe(x.full);
            if (x.clipped) clipped.push(`${path}「${label}」`);
          }
        }
        const first = page.locator("main table").nth(t).locator("tbody tr").filter({ has: page.locator("td") }).first().locator("td").nth(ci);
        const full = col.cells[0]?.texts.length === 1 ? col.cells[0].texts[0].full : "";
        if (full) await expect.soft(first, `${name}「${label}」1 行目: アクセシブル名が全文`).toHaveAccessibleName(full);
      }
      if (num) seenNumeric.add(label);
      const where = `${name}「${label}」`;
      expect.soft(isRight(col.headAlign), `${where}: 見出しは${num ? "右" : "左"}寄せ (${col.headAlign})`).toBe(num);
      if (col.icon) {
        expect.soft(col.icon.left >= col.label.right - TOLERANCE, `${where}: ソートの矢印が文字の右 (矢印 ${col.icon.left} / 文字の右端 ${col.label.right})`).toBe(true);
      }
      for (const [r, cell] of col.cells.entries()) {
        const at = `${where} ${r + 1} 行目`;
        expect.soft(isRight(cell.align), `${at}: セルは${num ? "右" : "左"}寄せ (${cell.align})`).toBe(num);
        // 中身の無いセル (操作の無い行) は端を測らない
        if (!cell.content) continue;
        if (num) {
          expect.soft(Math.abs(cell.content.right - col.label.right), `${at}: 右端が見出しの文字とそろう (セル ${cell.content.right} / 見出し ${col.label.right})`).toBeLessThanOrEqual(TOLERANCE);
        } else {
          expect.soft(Math.abs(cell.content.left - col.label.left), `${at}: 左端が見出しの文字とそろう (セル ${cell.content.left} / 見出し ${col.label.left})`).toBeLessThanOrEqual(TOLERANCE);
        }
        // 操作のボタンの並びは、縦の中心がセルの中心にそろう (狭い幅で折り返したときは並び全体で見る)
        if (cell.buttons.length > 0) {
          const center = (cell.cell.top + cell.cell.bottom) / 2;
          const top = Math.min(...cell.buttons.map((b) => b.top));
          const bottom = Math.max(...cell.buttons.map((b) => b.bottom));
          expect.soft(Math.abs((top + bottom) / 2 - center), `${at}: ボタンの並びの縦の中心がセルの中心`).toBeLessThanOrEqual(TOLERANCE);
        }
      }
    }
    if (fit) {
      // 1 明細の行 (出荷指示以外は全行) の高さは 1 種類
      const heights = [...new Set(table.rows.filter((r) => r.lines <= 1).map((r) => r.height))];
      expect.soft(heights, `${name}: 行の高さがそろう`).toHaveLength(1);
      for (const [c, box] of table.containers.entries()) {
        expect.soft(box.scroll, `${name}: 容器 ${c + 1} が横にスクロールしない (scrollWidth ${box.scroll} / clientWidth ${box.client})`).toBeLessThanOrEqual(box.client);
      }
      expect.soft(table.table, `${name}: 表の幅がパネルの中に収まる (表 ${table.table} / パネル ${table.main})`).toBeLessThanOrEqual(table.main + TOLERANCE);
    }
  }
  expect([...seenNumeric].sort(), `${path}: 数値の列がそろって見つかる`).toEqual([...numeric].sort());
  return clipped;
}
