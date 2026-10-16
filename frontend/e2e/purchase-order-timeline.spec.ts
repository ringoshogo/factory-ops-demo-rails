import { expect, test, type Page } from "@playwright/test";
import { login } from "./support/world";

// 発注の詳細の進みは、API が古い順に並べた出来事を上から出す。同じ日の出荷・検収・請求書の受領は、時刻を持つ出来事の後ろに
// 業務の順で並ぶ (docs/architecture/graphql-schema.md「発注側の視点」)。E2E の世界 (lib/demo_world.rb) の発注は、
// どれもシードを流した日に進めるので、出来事はすべて同じ日になる

const kinds = (page: Page) => page.getByTestId("timeline-entry").evaluateAll((entries) => entries.map((e) => e.getAttribute("data-kind")));

/** 一覧を開き、条件に合う最初の行の詳細へ移る。 */
async function openFirst(page: Page, list: string, row: (rows: ReturnType<Page["getByTestId"]>) => ReturnType<Page["getByTestId"]>) {
  await page.goto(list);
  const href = await row(page.getByTestId("list-row")).first().locator('a[href^="/buyer/purchase-orders/"]').first().getAttribute("href");
  expect(href, `${list} に条件に合う行がある`).toBeTruthy();
  await page.goto(href!);
}

test("請求書を発行した発注は、発注登録 → 受注確定 → 出荷 → 検収 → 請求書の受領の順に出る", async ({ page }, testInfo) => {
  await login(page, testInfo, "granted_buyer_member");
  // 世界の発注側の検収済の発注 (検収のみ・請求の下書き・請求書の発行) のうち、明細が 2 行なのは請求書を発行した発注だけである
  await openFirst(page, "/buyer/purchase-orders?status=INSPECTED", (rows) =>
    rows.filter({ has: page.getByRole("cell", { name: "2 件", exact: true }) }),
  );

  await expect(page.getByTestId("timeline-entry")).toHaveCount(5);
  expect(await kinds(page)).toEqual(["ORDERED", "ACCEPTED", "SHIPPED", "INSPECTED", "INVOICE_RECEIVED"]);
  const entries = page.getByTestId("timeline-entry");
  await expect(entries.nth(0)).toContainText("発注登録");
  await expect(entries.nth(4)).toContainText("請求書の受領");
  // 時刻を持つ出来事は日付と時刻を、日付だけの出来事は日付だけを出す
  await expect(entries.nth(1).locator("time")).toHaveText(/\d+月\d+日 \d{2}:\d{2}$/);
  await expect(entries.nth(2).locator("time")).toHaveText(/^\d+月\d+日$/);
});

test("取消依頼中の発注には取消依頼が出て、出荷は出ない", async ({ page }, testInfo) => {
  await login(page, testInfo, "granted_buyer_member");
  await openFirst(page, "/buyer/purchase-orders?status=ACCEPTED", (rows) =>
    rows.filter({ has: page.getByTestId("status-mark").filter({ hasText: "取消依頼中" }) }),
  );

  // 対照：取消依頼は出る
  await expect(page.getByTestId("timeline-entry").filter({ hasText: "取消依頼" })).toHaveCount(1);
  expect(await kinds(page)).toEqual(["ORDERED", "ACCEPTED", "CANCELLATION_REQUESTED"]);
  await expect(page.locator('[data-testid="timeline-entry"][data-kind="SHIPPED"]')).toHaveCount(0);
});
