import { expect, type Locator } from "@playwright/test";
import { parseColor, parseShadow } from "./contrast";
import { ALPHA_TOLERANCE, PX_TOLERANCE, type Rgba, type ShadowLayer } from "./tokens";

/** 計算済みスタイルとトークンの比べ方 (仕様 cycle-03 §2: 色は rgb 一致・不透明度 ±0.01、寸法 ±0.5px)。 */

export const css = (target: Locator, prop: string) =>
  target.evaluate((el, p) => getComputedStyle(el).getPropertyValue(p), prop);

export function expectColor(actual: string, expected: Rgba, label: string) {
  const color = parseColor(actual);
  expect(color, `${label}: rgb で読める色 (${actual})`).not.toBeNull();
  const [r, g, b, a] = color!;
  expect([r, g, b], `${label}: ${actual}`).toEqual(expected.slice(0, 3));
  expect(Math.abs(a - expected[3]), `${label}: 不透明度 ${a} ≠ ${expected[3]}`).toBeLessThanOrEqual(ALPHA_TOLERANCE);
}

export function colorMatches(actual: string, expected: Rgba): boolean {
  const color = parseColor(actual);
  return (
    color !== null &&
    color.slice(0, 3).every((v, i) => v === expected[i]) &&
    Math.abs(color[3] - expected[3]) <= ALPHA_TOLERANCE
  );
}

export function expectPx(actual: string, expected: number, label: string) {
  expect(Math.abs(parseFloat(actual) - expected), `${label}: ${actual} ≠ ${expected}px`).toBeLessThanOrEqual(
    PX_TOLERANCE,
  );
}

export function expectShadow(actual: string, expected: ShadowLayer[], label: string) {
  const layers = parseShadow(actual);
  expect(layers.length, `${label}: 層の数 (${actual})`).toBe(expected.length);
  expected.forEach((want, i) => {
    const got = layers[i];
    const name = `${label} の ${i + 1} 層目`;
    expect(got.inset, `${name}: inset`).toBe(want.inset);
    expect([got.x, got.y, got.blur, got.spread], `${name}: 長さ`).toEqual([want.x, want.y, want.blur, want.spread]);
    expectColor(`rgba(${got.color.join(", ")})`, want.color, `${name}: 色`);
  });
}


/** `expect.poll` で待つための判定 (ホバー後の影など)。比べ方は expectShadow と同じ。 */
export function shadowMatches(actual: string, expected: ShadowLayer[]): boolean {
  const layers = parseShadow(actual);
  return (
    layers.length === expected.length &&
    expected.every((want, i) => {
      const got = layers[i];
      return (
        got.inset === want.inset &&
        [got.x, got.y, got.blur, got.spread].every((v, j) => v === [want.x, want.y, want.blur, want.spread][j]) &&
        colorMatches(`rgba(${got.color.join(", ")})`, want.color)
      );
    })
  );
}
