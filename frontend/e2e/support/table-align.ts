import { expect, type Page } from "@playwright/test";

/**
 * 表の列のそろえ。
 *
 * - 数値の列だけ見出しもセルも右寄せ。ほかの列 (操作を含む) は左寄せ
 * - 見出しの**文字**とセルの中身の端が 1px 以内でそろう (左寄せの列は左端、右寄せの列は右端)
 * - ソートの矢印はどの列も文字の右
 * - 1280・1024 で表がパネル (main) に収まる (表の容器が横にスクロールしない)
 * - 長い文字の列は折り返さず、収まらなければ末尾を省略する。全文は title とアクセシブル名で読める
 *
 * 文字の端は Range で測る (見出しのボタンの矢印を含めない)。セルは文字と、行の中に置かれた箱
 * (ボタン・バッジ) の外接矩形で測る (操作の並びのようなブロックの容器はセルの幅いっぱいなので数えない)。
 */

/** 1280・1024 は表がパネルに収まる。390 は表の容器の中で横にスクロールしてよい 。 */
export const FIT_WIDTHS = [1280, 1024];

const TOLERANCE = 1;

type Edge = { left: number; right: number };
type Column = {
  head: string;
  headAlign: string;
  /** 見出しの文字。文字の無い見出し (操作の列) は null */
  label: Edge | null;
  /** ソートの矢印。ソートできない見出しは null */
  icon: Edge | null;
  cells: {
    align: string;
    content: Edge | null;
    onlyButtons: boolean;
    buttons: { top: number; bottom: number }[];
    cell: { top: number; bottom: number };
    /** 省略できる文字 (title を持つ要素) ごとの title・全文・省略されているか */
    texts: { title: string | null; full: string; clipped: boolean }[];
  }[];
};
type Measured = {
  columns: Column[];
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
          label: textEdge(labelNodes),
          icon: svg ? box(svg.getBoundingClientRect()) : null,
          cells: rows.map((tr) => {
            const td = tr.children[i] as HTMLElement;
            const r = td.getBoundingClientRect();
            return {
              align: getComputedStyle(td).textAlign,
              content: textEdge([td]),
              // 表示されているボタンだけ (幅で出し分けて隠れている方は数えない)
              // ボタンの外に文字のあるセル (状態の文字の下に切り替えのボタンを置くセル) は、ボタンの並びの中心を測らない
              onlyButtons:
                [...td.querySelectorAll("button")].length > 0 &&
                [...td.querySelectorAll("*")].every((el) => el.closest("button") || ![...el.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && n.textContent!.trim() !== "")) &&
                ![...td.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && n.textContent!.trim() !== ""),
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
      return { columns, containers, table: table.getBoundingClientRect().width, main: mainWidth };
    });
  });
}

const isRight = (align: string) => align === "right" || align === "end";

/**
 * 今の画面の全部の表について、そろえ・省略・はみ出しを検査する。失敗はまとめて出す (expect.soft)。
 *
 * 数値の列は見出しの寄せ (右寄せ) から読み、セルの寄せが見出しと同じことを確かめる。画面ごとに数値の列を手で
 * 並べないので、画面を足しても一覧を直さずに測れる。セルの中身の端は、左寄せの列は左端、右寄せの列は右端が、
 * 見出しの文字と 1px 以内でそろう。省略できる文字 (data-truncate) は title に全文を持つ。
 * `fit` が真 (1280・1024) なら、表がパネルに収まり、表の容器が横にスクロールしないことも見る。
 */
export async function expectTablesAligned(page: Page, path: string, fit: boolean): Promise<void> {
  // 文字の幅で列の幅が変わるので、Web フォントの読み込みを待ってから測る
  await page.evaluate(() => document.fonts.ready);
  const tables = await measure(page);

  for (const [t, table] of tables.entries()) {
    const name = `${path} の表 ${t + 1}`;
    for (const col of table.columns) {
      const label = col.head.trim();
      const where = `${name}「${label}」`;
      const num = isRight(col.headAlign);
      if (col.icon) {
        expect.soft(col.icon.left >= (col.label?.right ?? 0) - TOLERANCE, `${where}: 並べ替えの矢印が文字の右 (矢印 ${col.icon.left} / 文字の右端 ${col.label?.right})`).toBe(true);
      }
      for (const [r, cell] of col.cells.entries()) {
        const at = `${where} ${r + 1} 行目`;
        expect.soft(isRight(cell.align), `${at}: セルの寄せが見出しと同じ (${cell.align} / ${col.headAlign})`).toBe(num);
        for (const x of cell.texts) expect.soft(x.title, `${at}: 省略できる文字の title が全文`).toBe(x.full);
        // 中身の無いセル (操作の無い行・空の行) は端を測らない
        if (!cell.content || !col.label) continue;
        if (num) {
          expect.soft(Math.abs(cell.content.right - col.label.right), `${at}: 右端が見出しの文字とそろう (セル ${cell.content.right} / 見出し ${col.label.right})`).toBeLessThanOrEqual(TOLERANCE);
        } else {
          expect.soft(Math.abs(cell.content.left - col.label.left), `${at}: 左端が見出しの文字とそろう (セル ${cell.content.left} / 見出し ${col.label.left})`).toBeLessThanOrEqual(TOLERANCE);
        }
        // 操作のボタンの並びは、縦の中心がセルの中心にそろう
        if (cell.onlyButtons) {
          const center = (cell.cell.top + cell.cell.bottom) / 2;
          const top = Math.min(...cell.buttons.map((bt) => bt.top));
          const bottom = Math.max(...cell.buttons.map((bt) => bt.bottom));
          expect.soft(Math.abs((top + bottom) / 2 - center), `${at}: ボタンの並びの縦の中心がセルの中心`).toBeLessThanOrEqual(TOLERANCE);
        }
      }
    }
    if (fit) {
      for (const [c, box] of table.containers.entries()) {
        expect.soft(box.scroll, `${name}: 容器 ${c + 1} が横にスクロールしない (scrollWidth ${box.scroll} / clientWidth ${box.client})`).toBeLessThanOrEqual(box.client);
      }
      expect.soft(table.table, `${name}: 表の幅がパネルの中に収まる (表 ${table.table} / パネル ${table.main})`).toBeLessThanOrEqual(table.main + TOLERANCE);
    }
  }
}
