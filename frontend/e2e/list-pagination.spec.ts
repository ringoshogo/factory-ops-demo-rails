import { expect, test, type Page } from "@playwright/test";
import { login } from "./support/world";

// 一覧は 1 ページ (20 件) ずつ読み、並べ替えと件数はサーバーが行う。E2E の世界の品目は 22 件で、1 ページを超える
// (spec/scenarios/demo_world_spec.rb が件数を確かめる)

const rows = (page: Page) => page.getByTestId("list-row");

async function codes(page: Page): Promise<string[]> {
  return rows(page).locator("td:first-child").allInnerTexts();
}

async function names(page: Page): Promise<string[]> {
  return rows(page).locator("td:nth-child(2)").allInnerTexts();
}

test("品目の一覧を名前の昇順で 2 ページ目まで読むと、1 ページ目と重ならず、合わせて totalCount の件数になる", async ({ page }, testInfo) => {
  await login(page, testInfo, "supplier_admin");
  await page.goto("/supplier/items?sort=name&dir=asc");
  const total = Number((await page.getByTestId("list-count").innerText()).replace(/[^0-9]/g, ""));
  expect(total).toBe(22);

  await expect(rows(page)).toHaveCount(20);
  const first = await codes(page);
  const firstNames = await names(page);

  await page.getByTestId("next-page").click();
  await expect(page).toHaveURL(/after=/);
  await expect(rows(page)).toHaveCount(total - 20);
  const second = await codes(page);
  const secondNames = await names(page);

  expect(first.filter((code) => second.includes(code))).toEqual([]);
  expect(new Set([...first, ...second]).size).toBe(total);
  // 名前の並びは DB の照合順序で決まり、画面の照合順序とは一致しないので、名前の順は比べない。名前も重ならない
  expect(firstNames.filter((name) => secondNames.includes(name))).toEqual([]);
  // 2 ページ目に次は無く、最初のページへ戻れる
  await expect(page.getByTestId("next-page")).toHaveCount(0);
  await page.getByTestId("first-page").click();
  await expect(page).not.toHaveURL(/after=/);
  expect(await codes(page)).toEqual(first);
});

test("並べ替えの見出しを押すと、URL の sort・dir と並びが変わり、1 ページ目に戻る", async ({ page }, testInfo) => {
  await login(page, testInfo, "supplier_admin");
  await page.goto("/supplier/items?sort=code&dir=asc");
  const ascending = await codes(page);
  await page.getByTestId("next-page").click();
  await expect(page).toHaveURL(/after=/);

  await page.getByRole("button", { name: "品目コード" }).click();
  await expect(page).toHaveURL(/sort=code&dir=desc/);
  await expect(page).not.toHaveURL(/after=/);
  await expect(page.getByRole("columnheader", { name: "品目コード" })).toHaveAttribute("aria-sort", "descending");
  const descending = await codes(page);
  expect(descending).toHaveLength(20);
  // 降順の 1 ページ目は、昇順の全件の後ろから 20 件を逆に並べたもの。昇順の 1 ページ目の先頭は降順の 1 ページ目に無い
  expect(descending[0] > ascending[0]).toBe(true);
  expect(descending).not.toContain(ascending[0]);
  expect([...descending].sort().reverse()).toEqual(descending);

  await page.getByRole("button", { name: "品目名" }).click();
  await expect(page).toHaveURL(/sort=name&dir=asc/);
});
