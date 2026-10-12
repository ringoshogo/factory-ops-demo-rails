import { test } from "@playwright/test";
import { APP_URL } from "../playwright.config";
import { openScreen, screenName, screenPlans } from "./support/screens";
import { login } from "./support/world";

// 検収表のスクリーンショット。画面 × ライト・ダーク × 1280・1024・390 を撮り、担当者が同じ種類の要素どうしを
// 見比べてから作者に見せる。撮るだけで何も確かめないので、E2E_SCREENSHOTS=1 のときだけ動く。
// npm run test:e2e の後に test-results/acceptance/ に残る

const THEMES = ["light", "dark"] as const;
const WIDTHS = [1280, 1024, 390];

test.skip(process.env.E2E_SCREENSHOTS !== "1", "検収表のスクリーンショットは E2E_SCREENSHOTS=1 のときだけ撮る");

for (const screen of screenPlans()) {
  test(`検収表: ${screen.route}${screen.variant}`, async ({ page }, testInfo) => {
    test.setTimeout(120_000);
    await login(page, testInfo, screen.persona);
    for (const theme of THEMES) {
      // テーマは Cookie で選ぶ (lib/theme.ts)。サーバーが描く時点で決まる
      await page.context().addCookies([{ name: "theme", value: theme, url: APP_URL }]);
      for (const width of WIDTHS) {
        await page.setViewportSize({ width, height: 900 });
        await openScreen(page, screen);
        await page.screenshot({ path: `test-results/acceptance/${screenName(screen)}-${theme}-${width}.png`, fullPage: true });
      }
    }
  });
}
