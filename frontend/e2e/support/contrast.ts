import AxeBuilder from "@axe-core/playwright";
import { expect, type Locator, type Page } from "@playwright/test";
import type { Rgba, ShadowLayer } from "./tokens";

/**
 * 図形のコントラスト (識別に要る図形・フォーカス 3:1。仕様 cycle-03 §2「AA を計測する対象」)。
 *
 * axe は文字しか判定しないので自前で測る。要素の計算済みの色を読み、背後の面を
 * 祖先へたどって半透明の色を合成してから比を出す。合成は各チャンネルを 0〜255 の
 * 整数に丸めてから輝度を出す (仕様の計算と同じ丸め方)。
 */

/** 計算済みスタイルの色の文字列 (`rgb()`・`rgba()`・`transparent`) を読む。読めなければ null。 */
export function parseColor(value: string): Rgba | null {
  const v = value.trim();
  if (v === "transparent") return [0, 0, 0, 0];
  const m = v.match(/^rgba?\(([^)]+)\)$/);
  if (!m) return null;
  const parts = m[1].split(/[\s,/]+/).filter(Boolean).map(Number);
  if (parts.length < 3 || parts.some(Number.isNaN)) return null;
  return [parts[0], parts[1], parts[2], parts[3] ?? 1];
}

/** 括弧の外にある区切り文字で分ける (`rgba(0, 0, 0, 0.1) 0px 1px, ...` の層を分ける)。 */
export function splitTopLevel(value: string, sep: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let current = "";
  for (const ch of value) {
    if (ch === "(") depth++;
    if (ch === ")") depth--;
    if (ch === sep && depth === 0) {
      out.push(current.trim());
      current = "";
    } else {
      current += ch;
    }
  }
  if (current.trim()) out.push(current.trim());
  return out;
}

/**
 * 計算済みの `box-shadow` を層に分ける。Chrome は「色 x y blur spread [inset]」の順で返す。
 * Tailwind が既定で積む空の層 (`0 0 #0000`。透明で長さがすべて 0) は数えない。
 */
export function parseShadow(value: string): ShadowLayer[] {
  if (value.trim() === "none") return [];
  return splitTopLevel(value, ",")
    .map((text) => {
      const colorText = text.match(/rgba?\([^)]*\)|transparent/)?.[0] ?? "";
      const rest = text.replace(colorText, " ").trim();
      const lengths = rest.match(/-?[\d.]+px|\b0\b/g)?.map((s) => parseFloat(s)) ?? [];
      const [x = 0, y = 0, blur = 0, spread = 0] = lengths;
      const color = parseColor(colorText);
      if (!color) throw new Error(`影の色を読めない: ${text}`);
      return { inset: /\binset\b/.test(rest), x, y, blur, spread, color };
    })
    .filter((l) => !(l.color[3] === 0 && l.x === 0 && l.y === 0 && l.blur === 0 && l.spread === 0));
}

/** `top` を `bottom` (不透明) の上に重ねた色。各チャンネルを整数に丸める。 */
export function composite(top: Rgba, bottom: Rgba): Rgba {
  const a = top[3];
  const ch = (i: number) => Math.round(top[i] * a + bottom[i] * (1 - a));
  return [ch(0), ch(1), ch(2), 1];
}

export function luminance([r, g, b]: Rgba): number {
  const lin = (c: number) => {
    const s = c / 255;
    return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

export function contrastRatio(a: Rgba, b: Rgba): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

/**
 * 要素の背後の面 (不透明に合成済み)。`includeSelf` で要素自身の背景も重ねる。
 *
 * 祖先の背景色を読み、`rgb()` 以外 (oklch 等) で返る色だけはブラウザの canvas で
 * RGB に直す。最上段の下地は白 (ブラウザの既定のキャンバス)。
 */
export async function backdrop(target: Locator, includeSelf: boolean): Promise<Rgba> {
  const chain = await target.evaluate((el, self) => {
    const toRgb = (color: string) => {
      if (/^rgba?\(/.test(color) || color === "transparent") return color;
      const canvas = document.createElement("canvas");
      canvas.width = canvas.height = 1;
      const ctx = canvas.getContext("2d")!;
      ctx.fillStyle = color;
      ctx.fillRect(0, 0, 1, 1);
      const [r, g, b, a] = ctx.getImageData(0, 0, 1, 1).data;
      return `rgba(${r}, ${g}, ${b}, ${a / 255})`;
    };
    const colors: string[] = [];
    let node: Element | null = self ? el : el.parentElement;
    while (node) {
      colors.push(toRgb(getComputedStyle(node).backgroundColor));
      node = node.parentElement;
    }
    return colors;
  }, includeSelf);

  let base: Rgba = [255, 255, 255, 1];
  for (const text of chain.reverse()) {
    const color = parseColor(text);
    if (!color) throw new Error(`背景色を読めない: ${text}`);
    if (color[3] > 0) base = composite(color, base);
  }
  return base;
}

/** 識別に要る図形・フォーカスの下限 (WCAG 1.4.11)。 */
export const SHAPE_MIN = 3;

/** 図形の色 (合成済み)・背後の面・比。報告と「どの面の上で測ったか」の確認に使う。 */
export type ShapeContrast = { ratio: number; shape: Rgba; behind: Rgba };

const computed = (target: Locator, prop: string) =>
  target.evaluate((el, p) => getComputedStyle(el).getPropertyValue(p), prop);

function readColor(text: string, label: string): Rgba {
  const color = parseColor(text);
  if (!color) throw new Error(`${label}の色を読めない: ${text}`);
  return color;
}

/**
 * 縁取り (`box-shadow` の `inset 0 0 0 1px`) と要素の外の面。縁の色は影の色を要素の面に合成した色
 * (入力欄・二次ボタン・絞り込みボタン・日付ボタン・主ボタンの縁)。
 */
export async function insetEdgeContrast(target: Locator): Promise<ShapeContrast> {
  const edge = parseShadow(await computed(target, "box-shadow")).find((l) => l.inset && l.spread === 1);
  expect(edge, "inset 0 0 0 1px の縁取りがある").toBeDefined();
  const shape = composite(edge!.color, await backdrop(target, true));
  const behind = await backdrop(target, false);
  return { ratio: contrastRatio(shape, behind), shape, behind };
}

/** 枠線 1 辺 (選択中のタブの下線) を要素の面に合成した色と、要素の外の面。 */
export async function borderContrast(target: Locator, side: "top" | "right" | "bottom" | "left"): Promise<ShapeContrast> {
  expect(await computed(target, `border-${side}-style`), `border-${side} の線`).toBe("solid");
  expect(parseFloat(await computed(target, `border-${side}-width`)), `border-${side} の太さ`).toBeGreaterThan(0);
  const line = readColor(await computed(target, `border-${side}-color`), "枠線");
  const shape = composite(line, await backdrop(target, true));
  const behind = await backdrop(target, false);
  return { ratio: contrastRatio(shape, behind), shape, behind };
}

/** 要素の面 (祖先の上に自分の背景を合成した色) と外の面 (選んでいる日付の面とポップオーバー)。 */
export async function faceContrast(target: Locator): Promise<ShapeContrast> {
  const shape = await backdrop(target, true);
  const behind = await backdrop(target, false);
  return { ratio: contrastRatio(shape, behind), shape, behind };
}

/**
 * 印 (`mark` の CSS プロパティ `prop` の色。バッジの点の `fill`・アイコンの `color`) と、
 * それが載る `face` の面。
 */
export async function markContrast(mark: Locator, prop: string, face: Locator): Promise<ShapeContrast> {
  const behind = await backdrop(face, true);
  const shape = composite(readColor(await computed(mark, prop), "印"), behind);
  return { ratio: contrastRatio(shape, behind), shape, behind };
}

/**
 * フォーカスの輪郭 (`outline`) と背後の面。`outline-offset` が 0 以上なら輪郭は要素の外に描かれるので
 * 背後は親の面、負なら要素の内側 (メニューの項目) なので要素自身の面。
 */
export async function focusRingContrast(target: Locator): Promise<ShapeContrast> {
  expect(await computed(target, "outline-style"), "輪郭の線").toBe("solid");
  expect(parseFloat(await computed(target, "outline-width")), "輪郭の太さ").toBeGreaterThanOrEqual(2);
  const inside = parseFloat(await computed(target, "outline-offset")) < 0;
  const behind = await backdrop(target, inside);
  const shape = composite(readColor(await computed(target, "outline-color"), "輪郭"), behind);
  return { ratio: contrastRatio(shape, behind), shape, behind };
}

/** Tab キーを押して `target` にフォーカスを移す (`focus()` では :focus-visible の状態にならないことがある)。 */
export async function tabTo(page: Page, target: Locator, max = 60) {
  const isActive = () => target.evaluate((el) => el === document.activeElement);
  // Base UI のフォーカスの番兵は、フォーカスを受けた次の描画で内外の要素へ移す。移り終わる前に
  // 次のキーを押すとフォーカスがダイアログの外へ落ちるので、1 回押すごとに 2 フレーム待つ
  const press = async (key: string) => {
    await page.keyboard.press(key);
    await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
  };
  // 押して開いたダイアログの初期フォーカスなど、キーボード以外で既にフォーカスがあるときは、
  // 一度前へ外して Tab キーで戻す
  if ((await isActive()) && !(await target.evaluate((el) => el.matches(":focus-visible")))) {
    await press("Shift+Tab");
  }
  for (let i = 0; i < max && !(await isActive()); i++) {
    await press("Tab");
  }
  await expect(target).toBeFocused();
  expect(await target.evaluate((el) => el.matches(":focus-visible")), "Tab キーで移した状態 (:focus-visible)").toBe(true);
}

/**
 * WCAG 2.1 A・AA の axe 違反 (文字の 4.5:1 を含む)。Base UI のフォーカスの番兵
 * (`data-base-ui-focus-guard`、aria-hidden・tabindex=0) は除く。番兵はフォーカスを受けた瞬間に
 * ポップアップの内外へ移すので aria-hidden-focus は当たらない。
 */
export async function wcagViolations(page: Page): Promise<string[]> {
  const result = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .exclude("[data-base-ui-focus-guard]")
    .analyze();
  return result.violations.flatMap((v) => v.nodes.map((n) => `${v.id} ${n.target.join(" ")}: ${n.failureSummary ?? ""}`));
}
