import { expect, type Locator } from "@playwright/test";

/**
 * select の矢印が右端から離れていること。ブラウザ標準の矢印は位置を
 * 調整できないので、標準の矢印を消し (appearance: none)、自前のアイコンを
 * 右端から内側に置く。文字が矢印に重ならない余白も確かめる。
 */
export async function expectArrowInset(scope: Locator) {
  const selects = scope.locator("select");
  const count = await selects.count();
  expect(count, "select がある").toBeGreaterThan(0);
  for (let i = 0; i < count; i++) {
    const m = await selects.nth(i).evaluate((el) => {
      const style = getComputedStyle(el);
      const icon = el.parentElement?.querySelector("svg");
      const box = el.getBoundingClientRect();
      const iconBox = icon?.getBoundingClientRect();
      return {
        appearance: style.appearance,
        gap: iconBox ? Math.round(box.right - iconBox.right) : -1,
        paddingRight: parseFloat(style.paddingRight),
        iconWidth: iconBox ? Math.round(iconBox.width) : 0,
        name: el.id || el.getAttribute("name"),
      };
    });
    expect(m.appearance, `${m.name}: 標準の矢印を消す`).toBe("none");
    expect(m.gap, `${m.name}: 矢印と右端の間`).toBeGreaterThanOrEqual(10);
    expect(m.paddingRight, `${m.name}: 文字が矢印に重ならない余白`).toBeGreaterThanOrEqual(m.gap + m.iconWidth);
  }
}
