import { expect, test } from "@playwright/test";
import { login } from "./support/world";

// 取り込みのファイルは、ブラウザから同じオリジンの /imports/files (app/imports/files/route.ts) へ送り、Next のサーバーが
// 実行の時の RAILS_URL の Rails へそのまま送る。返ったファイルで取り込みを始め、bin/jobs が流し終えるまで、
// 進み具合の画面が読み直す

test("在庫の CSV を送ると取り込みの進み具合の画面に移り、一部失敗と失敗した行が出る", async ({ page }, testInfo) => {
  await login(page, testInfo, "supplier_admin");
  await page.goto("/supplier/imports");
  await page.getByLabel("種類").selectOption("STOCKS");
  await page.getByLabel("CSV ファイル").setInputFiles({
    name: "stocks.csv",
    mimeType: "text/csv",
    buffer: Buffer.from("item_code,quantity\nITM-001,3\nNO-SUCH-ITEM,1\n"),
  });
  await page.getByRole("button", { name: "取り込む" }).click();

  await expect(page).toHaveURL(/\/supplier\/imports\/[0-9a-f-]{36}$/);
  // ワーカーの処理を待つ。固定の時間は待たず、終わった状況になるまで読み直す
  await expect
    .poll(
      async () => {
        await page.reload();
        return page.getByTestId("import-status").getAttribute("data-status");
      },
      { timeout: 30_000, intervals: [500, 1000, 2000] },
    )
    .toBe("PARTIALLY_FAILED");
  await expect(page.getByTestId("row-error")).toHaveCount(1);
  await expect(page.getByTestId("row-error")).toContainText("3");
});
