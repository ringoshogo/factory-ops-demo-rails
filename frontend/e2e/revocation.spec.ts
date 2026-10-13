import { expect, test, type Page } from "@playwright/test";
import { login } from "./support/world";

// 重要シナリオ S2 (取引関係の失効) を画面で通す (docs/guides/testing.md「重要シナリオ」)。失効で、発注側から見た
// 取引先・カタログ・出荷 (経路 3) が閉じ、開いていた発注の登録が NOT_PERMITTED の 1 つの文言になる。
// 世界の発注側のうち失効済みの 1 社と結び直してから失効させるので、終わったときの世界は始めと同じく失効済みのまま。
// 発注側と受注側は別の context でログインする。同じ context でログインし直すと、ログアウトがセッションの世代を進める

// lib/graphql/user-errors.ts の NOT_PERMITTED_MESSAGE と同じ文言
const NOT_PERMITTED = "この取引先とは、この操作をできません。取引関係と権限の付与を確かめてください。";

const PERMISSIONS = ["カタログを見る", "発注する", "出荷を見る"];

async function partnershipRow(page: Page, buyerName: string, status: "ACTIVE" | "REVOKED") {
  return page.getByTestId("list-row").and(page.locator(`[data-status="${status}"]`)).filter({ hasText: buyerName });
}

test("失効で、発注側の取引先・カタログ・出荷が空になり、開いていた発注の登録が NOT_PERMITTED の文言になる", async ({ browser }, testInfo) => {
  const buyer = await (await browser.newContext()).newPage();
  const supplier = await (await browser.newContext()).newPage();
  await login(buyer, testInfo, "revoked_buyer_admin");
  await login(supplier, testInfo, "supplier_admin");
  const buyerName = await buyer.getByTestId("tenant-name").first().innerText();

  // 失効済みなので、始めは取引先が無い (対照の前提)
  await buyer.goto("/buyer/suppliers");
  await expect(buyer.getByTestId("empty-suppliers")).toBeVisible();

  // 発注側の管理者が取引用コードを読み、受注側の管理者が結び直して 3 つの権限を付与する
  await buyer.goto("/settings");
  const partnerCode = (await buyer.getByTestId("partner-code").innerText()).trim();
  expect(partnerCode).not.toBe("");

  await supplier.goto("/supplier/partnerships");
  await expect(await partnershipRow(supplier, buyerName, "ACTIVE")).toHaveCount(0);
  await supplier.getByRole("button", { name: "取引関係を結ぶ" }).click();
  await supplier.getByLabel("取引用コード").fill(partnerCode);
  await supplier.getByRole("button", { name: "結ぶ", exact: true }).click();
  const active = await partnershipRow(supplier, buyerName, "ACTIVE");
  await expect(active).toHaveCount(1);
  for (const permission of PERMISSIONS) {
    await active.getByRole("button", { name: `${permission}を付与` }).click();
    await expect(active.getByRole("button", { name: `${permission}を撤回` })).toBeVisible();
  }

  // 対照：結び直した間は、取引先・カタログ・出荷が見える
  await buyer.goto("/buyer/suppliers");
  const supplierLink = buyer.getByTestId("supplier-row").getByRole("link");
  await expect(supplierLink).toHaveCount(1);
  const supplierId = new URL((await supplierLink.getAttribute("href"))!, "http://x").searchParams.get("supplier")!;
  await supplierLink.click();
  await expect(buyer.getByTestId("catalog-row").first()).toBeVisible();

  await buyer.goto("/buyer/purchase-orders?tab=inbound");
  await buyer.getByTestId("list-row").first().getByRole("link").first().click();
  await expect(buyer.getByTestId("supplier-shipment-row").first()).toBeVisible();
  const orderUrl = buyer.url();

  // 発注の登録の画面を、その取引先で開いておく
  const form = await (await browser.newContext({ storageState: await buyer.context().storageState() })).newPage();
  await form.goto(`/buyer/purchase-orders/new?supplier=${supplierId}`);
  await form.getByLabel("自社品番").fill("KA-001");
  await form.getByLabel("数量").fill("1");

  // 受注側が失効させる
  await active.getByRole("button", { name: "失効させる" }).click();
  await supplier.getByRole("dialog").getByRole("button", { name: "失効させる" }).click();
  await expect(await partnershipRow(supplier, buyerName, "ACTIVE")).toHaveCount(0);

  // 発注側：取引先・カタログ・出荷が空になり、開いていた発注は NOT_PERMITTED の文言になる
  await form.getByRole("button", { name: "発注を登録" }).click();
  await expect(form.getByTestId("form-error")).toHaveText(NOT_PERMITTED);
  await expect(form).toHaveURL(/\/buyer\/purchase-orders\/new/);

  await buyer.goto("/buyer/suppliers");
  await expect(buyer.getByTestId("empty-suppliers")).toBeVisible();
  await buyer.goto(`/buyer/suppliers?supplier=${supplierId}`);
  await expect(buyer.getByTestId("catalog-row")).toHaveCount(0);
  // 届かないときとトップレベルのエラーも同じ list-error に出るので、見られないことの文言で確かめる
  await expect(buyer.getByTestId("list-error")).toHaveText(/この取引先のカタログは見られません/);
  await buyer.goto(orderUrl);
  await expect(buyer.getByTestId("supplier-shipments-empty")).toBeVisible();
  await expect(buyer.getByTestId("supplier-shipment-row")).toHaveCount(0);
});
