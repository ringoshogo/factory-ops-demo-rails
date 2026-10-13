import { expect, type Locator, type Page } from "@playwright/test";

/**
 * 日付の入力。日付はボタンで開くカレンダーで選び、
 * 送る値は隠し入力の YYYY-MM-DD に入る。E2E の日付の入力はこの 2 つの関数だけを通す。
 */

/** 開いているカレンダー (名前「日付を選ぶ」のダイアログ)。ポップオーバーは自分の Portal に描かれる。 */
export const calendar = (page: Page) => page.getByRole("dialog", { name: "日付を選ぶ" });

/** "2026-10-08" → "2026年10月8日" (日付のボタン・格子の日のボタンの表示)。 */
export function fullDate(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return `${y}年${m}月${d}日`;
}

const pageOf = (scope: Page | Locator): Page => ("page" in scope ? scope.page() : scope);

/**
 * 項目名のボタンを押す → 年・月の選択欄で iso の年月にする → 名前「YYYY年M月D日」の日を押す
 * → カレンダーが閉じ、ボタンの表示が変わったことを待つ。
 */
export async function pickDate(scope: Page | Locator, label: string, iso: string) {
  const page = pageOf(scope);
  const button = scope.getByLabel(label, { exact: true });
  await button.click();
  const dialog = calendar(page);
  await expect(dialog).toBeVisible();
  const [year, month] = iso.split("-").map(Number);
  await dialog.getByLabel("年", { exact: true }).selectOption(String(year));
  await dialog.getByLabel("月", { exact: true }).selectOption(String(month));
  await dialog.getByRole("gridcell").getByRole("button", { name: fullDate(iso), exact: true }).click();
  await expect(dialog).toHaveCount(0);
  await expect(button).toHaveText(fullDate(iso));
}

/** 送る値 (name の隠し入力) が iso であること。 */
export async function expectDateValue(scope: Page | Locator, name: string, iso: string) {
  await expect(scope.locator(`input[type="hidden"][name="${name}"]`)).toHaveValue(iso);
}

/** 項目名のボタンでカレンダーを開き、「日付を消す」で値を外す (期間の絞り込みの clearable な日付)。 */
export async function clearDate(scope: Page | Locator, label: string) {
  const page = pageOf(scope);
  const button = scope.getByLabel(label, { exact: true });
  await button.click();
  const dialog = calendar(page);
  await expect(dialog).toBeVisible();
  await dialog.getByRole("button", { name: "日付を消す" }).click();
  await expect(dialog).toHaveCount(0);
  await expect(button).toHaveText("日付を選ぶ");
}
