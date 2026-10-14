import { expect, test, type Browser, type Page, type TestInfo } from "@playwright/test";
import { login, type Persona } from "./support/world";

// admin に限る操作のボタンは、viewer.role が admin のときだけ出す (docs/architecture/graphql-schema.md「役割による制限」)。
// member に出すと、押しても Rails が FORBIDDEN で拒むだけの、押せるのに通らないボタンになる。どの画面も、同じ世界の
// admin で開いてボタンが出ること (対照) を確かめてから、member で開いて出ないことを確かめる

async function as(browser: Browser, testInfo: TestInfo, persona: Persona): Promise<Page> {
  const page = await (await browser.newContext()).newPage();
  await login(page, testInfo, persona);
  return page;
}

/** 一覧の行のうち、条件に合う最初の行の詳細へのリンクの道。 */
async function firstDetail(page: Page, list: string, prefix: string, mark?: string): Promise<string> {
  await page.goto(list);
  let rows = page.getByTestId("list-row");
  if (mark) rows = rows.filter({ has: page.getByTestId("status-mark").filter({ hasText: mark }) });
  const href = await rows.first().locator(`a[href^="${prefix}"]`).first().getAttribute("href");
  expect(href, `${list} に詳細へのリンクがある`).toBeTruthy();
  return href!;
}

test("受注詳細の取消と、取消の審査の承認・却下", async ({ browser }, testInfo) => {
  const admin = await as(browser, testInfo, "supplier_admin");
  const member = await as(browser, testInfo, "supplier_member");
  const received = await firstDetail(admin, "/supplier/sales-orders?status=RECEIVED", "/supplier/sales-orders/");
  const reviewing = await firstDetail(admin, "/supplier/sales-orders?status=ALLOCATED", "/supplier/sales-orders/", "取消審査中");

  await admin.goto(received);
  await expect(admin.getByRole("button", { name: "この受注を取り消す" })).toBeVisible();
  await admin.goto(reviewing);
  await expect(admin.getByRole("button", { name: "取消を承認" })).toBeVisible();
  await expect(admin.getByRole("button", { name: "取消を却下" })).toBeVisible();

  await member.goto(received);
  await expect(member.getByTestId("order-line").first()).toBeVisible();
  await expect(member.getByRole("button", { name: "この受注を取り消す" })).toHaveCount(0);
  await member.goto(reviewing);
  await expect(member.getByTestId("cancellation-review")).toBeVisible();
  await expect(member.getByRole("button", { name: /取消を(承認|却下)/ })).toHaveCount(0);
});

test("発注詳細の検収と取消依頼", async ({ browser }, testInfo) => {
  const admin = await as(browser, testInfo, "granted_buyer_admin");
  const member = await as(browser, testInfo, "granted_buyer_member");
  const inbound = await firstDetail(admin, "/buyer/purchase-orders?tab=inbound", "/buyer/purchase-orders/");
  // 取消依頼は出荷の前の発注にだけ出す。回答を待つ依頼のある発注には重ねて出さないので、印の無い行を選ぶ
  await admin.goto("/buyer/purchase-orders?status=ACCEPTED");
  const accepted = await admin
    .getByTestId("list-row")
    .filter({ hasNot: admin.getByTestId("status-mark") })
    .first()
    .locator('a[href^="/buyer/purchase-orders/"]')
    .first()
    .getAttribute("href");
  expect(accepted, "印の無い受注済の発注がある").toBeTruthy();

  await admin.goto(inbound);
  await expect(admin.getByRole("button", { name: "検収する" })).toBeVisible();
  // 入荷予定の発注は出荷した後なので、取消依頼を出さない
  await expect(admin.getByRole("button", { name: "取消を依頼する" })).toHaveCount(0);
  await admin.goto(accepted!);
  await expect(admin.getByRole("button", { name: "取消を依頼する" })).toBeVisible();

  await member.goto(inbound);
  await expect(member.getByTestId("inbound-shipment").first()).toBeVisible();
  await expect(member.getByRole("button", { name: "検収する" })).toHaveCount(0);
  await member.goto(accepted!);
  await expect(member.getByTestId("order-line").first()).toBeVisible();
  await expect(member.getByRole("button", { name: "取消を依頼する" })).toHaveCount(0);
});

test("取引関係を結ぶ・失効させる・権限を変える", async ({ browser }, testInfo) => {
  const admin = await as(browser, testInfo, "supplier_admin");
  const member = await as(browser, testInfo, "supplier_member");

  await admin.goto("/supplier/partnerships");
  await expect(admin.getByRole("button", { name: "取引関係を結ぶ" })).toBeVisible();
  await expect(admin.getByRole("button", { name: "失効させる" }).first()).toBeVisible();

  await member.goto("/supplier/partnerships");
  await expect(member.locator("main tbody tr").first()).toBeVisible();
  await expect(member.getByRole("button", { name: /取引関係を結ぶ|失効させる|^[＋−] / })).toHaveCount(0);
});

test("取り込みの種類の「品目と単価」", async ({ browser }, testInfo) => {
  const admin = await as(browser, testInfo, "supplier_admin");
  const member = await as(browser, testInfo, "supplier_member");

  await admin.goto("/supplier/imports");
  await expect(admin.getByLabel("種類").locator("option")).toHaveText(["在庫", "品目と単価"]);

  await member.goto("/supplier/imports");
  await expect(member.getByLabel("種類").locator("option")).toHaveText(["在庫"]);
});

test("自社の取引用コードと監査ログ", async ({ browser }, testInfo) => {
  const admin = await as(browser, testInfo, "supplier_admin");
  const member = await as(browser, testInfo, "supplier_member");

  await admin.goto("/settings");
  await expect(admin.getByTestId("partner-code")).toHaveText(/^[0-9a-f]{32}$/);
  await expect(admin.getByRole("link", { name: "監査ログ" }).first()).toBeVisible();
  await admin.goto("/audit-logs");
  await expect(admin.getByTestId("admin-only")).toHaveCount(0);

  await member.goto("/settings");
  await expect(member.getByText("管理者だけが見られます")).toBeVisible();
  await expect(member.getByTestId("partner-code")).toHaveCount(0);
  await expect(member.getByRole("link", { name: "監査ログ" })).toHaveCount(0);
  await member.goto("/audit-logs");
  await expect(member.getByTestId("admin-only")).toBeVisible();
});
