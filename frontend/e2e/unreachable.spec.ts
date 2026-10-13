import { expect, test } from "@playwright/test";
import { UNREACHABLE_APP_URL } from "../playwright.config";
import { login } from "./support/world";

// API に届かない画面。届かない URL を向いた Next を、同じホストの別のポートに立てている。Cookie はポートで分かれないので、
// 届く方の Next でログインした Cookie がそのまま届き、Next のサーバーが Rails を呼んで接続を拒まれる

const UNREACHABLE = "API に接続できませんでした。時間をおいてもう一度お試しください。";

for (const path of ["/supplier/sales-orders", "/buyer/purchase-orders"]) {
  test(`${path}: Rails に届かなければ、表を出さずに「API に接続できませんでした」を出す`, async ({ page }, testInfo) => {
    await login(page, testInfo, "supplier_admin");
    // 対照：届く方の Next では表が出る
    await page.goto(path);
    await expect(page.locator("main table")).toBeVisible();

    await page.goto(`${UNREACHABLE_APP_URL}${path}`);
    await expect(page.getByTestId("list-error")).toHaveText(UNREACHABLE);
    await expect(page.locator("main table")).toHaveCount(0);
  });
}
