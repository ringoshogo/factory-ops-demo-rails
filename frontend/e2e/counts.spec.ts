import { expect, test, type Page } from "@playwright/test";
import { login } from "./support/world";

// 集計の数字と、そこから飛ぶ一覧は、同じ条件で数える。ダッシュボードの状況ごとの件数・受注一覧を状況で絞った件数・
// かんばんの列の件数は、どれも API の同じ状況の式で数えるので一致する。安全在庫を下回る在庫の件数も同じ

const STATUSES = [
  "AWAITING_PART_MATCH",
  "RECEIVED",
  "PARTIALLY_ALLOCATED",
  "ALLOCATED",
  "SHIPPED",
  "INSPECTED",
  "CANCELLED",
] as const;

const number = async (page: Page, text: Promise<string>) => Number((await text).replace(/[^0-9]/g, ""));

test("状況ごとの件数が、ダッシュボード・受注一覧・かんばんの列で一致する", async ({ page }, testInfo) => {
  await login(page, testInfo, "supplier_admin");
  await page.goto("/supplier/dashboard");
  const dashboard: Record<string, number> = {};
  const kanban: Record<string, number> = {};
  for (const status of STATUSES) {
    dashboard[status] = await number(
      page,
      page.locator(`[data-testid="status-count"][data-status="${status}"] [data-testid="status-count-value"]`).innerText(),
    );
    kanban[status] = await number(
      page,
      page.locator(`[data-testid="kanban-column"][data-status="${status}"] [data-testid="kanban-count"]`).innerText(),
    );
  }
  // 空振りしない：世界は 7 つの状況のどれにも受注を持つ
  for (const status of STATUSES) expect(dashboard[status], status).toBeGreaterThan(0);
  expect(kanban).toEqual(dashboard);

  for (const status of STATUSES) {
    await page.goto(`/supplier/sales-orders?status=${status}`);
    expect(await number(page, page.getByTestId("list-count").innerText()), status).toBe(dashboard[status]);
  }
});

test("安全在庫を下回る在庫の件数が、ダッシュボードと在庫の画面の切り替えで一致する", async ({ page }, testInfo) => {
  await login(page, testInfo, "supplier_admin");
  await page.goto("/supplier/dashboard");
  const alerts = await number(page, page.getByTestId("stock-alerts-count").innerText());
  expect(alerts).toBeGreaterThan(0);

  await page.goto("/supplier/stocks?below=1");
  expect(await number(page, page.getByTestId("list-count").innerText())).toBe(alerts);
  // 対照：絞らなければ、下回らない在庫も数える
  await page.goto("/supplier/stocks");
  expect(await number(page, page.getByTestId("list-count").innerText())).toBeGreaterThan(alerts);
});
