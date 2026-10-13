import { expect, test, type Page } from "@playwright/test";
import { login, logout } from "./support/world";

// テナントを切り替えるには、ログアウトして別のテナントのユーザーでログインする。前のテナントの伝票が、後のテナントの
// 画面に出ないことを確かめる。発注番号はテナントごとに振るので 2 社で同じ番号がありうる。伝票は ID と、
// 明細の自社品番の接頭辞 (世界の発注側の 2 社は TS- と KA-) で見分ける

async function orderLinks(page: Page): Promise<string[]> {
  await page.goto("/buyer/purchase-orders");
  const links = page.getByTestId("list-row").locator("td:first-child a");
  await expect(links.first()).toBeVisible();
  return (await links.evaluateAll((as) => as.map((a) => (a as HTMLAnchorElement).pathname)));
}

async function partNumbers(page: Page, path: string): Promise<string[]> {
  await page.goto(path);
  return page.getByTestId("order-line").locator("td:first-child").allInnerTexts();
}

test("発注側の 2 社で続けてログインすると、前のテナントの発注が一覧にも詳細にも出ない", async ({ page }, testInfo) => {
  await login(page, testInfo, "granted_buyer_admin");
  const first = await orderLinks(page);
  // 対照：前のテナントでは、自社の発注が一覧に並び、詳細に自社の品番が出る
  expect(first.length).toBeGreaterThan(0);
  expect(await partNumbers(page, first[0])).toEqual(expect.arrayContaining([expect.stringMatching(/^TS-/)]));
  await logout(page);

  await login(page, testInfo, "revoked_buyer_admin");
  const second = await orderLinks(page);
  expect(second.filter((path) => first.includes(path))).toEqual([]);
  for (const path of second) {
    const parts = await partNumbers(page, path);
    expect(parts.length).toBeGreaterThan(0);
    expect(parts.filter((part) => !part.startsWith("KA-"))).toEqual([]);
  }
  // 前のテナントの発注の詳細は、見つからない画面になる (無いのか見えないのかを言い分けない)
  await page.goto(first[0]);
  await expect(page.getByTestId("not-found")).toBeVisible();
});
