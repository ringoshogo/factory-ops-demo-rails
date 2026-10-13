import { expect, test } from "@playwright/test";
import { APP_URL } from "../playwright.config";
import { wcagViolations } from "./support/contrast";
import { openScreen, screenPlans } from "./support/screens";
import { login } from "./support/world";

// 全画面をライトとダークで開き、WCAG 2.1 A・AA の axe の違反 (文字の 4.5:1 のコントラストを含む) が無いことを
// 確かめる。色のトークンは globals.css にだけ置き、画面ごとに色を書かないので、違反は画面の作り (トークンを使わない
// 色・背景の重ね方) か、要素の名前の付け忘れから来る。測る画面は寸法と同じ一覧 (e2e/support/screens.ts)

const THEMES = ["light", "dark"] as const;

for (const screen of screenPlans()) {
  const label = `${screen.route}${screen.variant}`;
  test(`${label}: ライトとダークで WCAG の違反が無い`, async ({ page }, testInfo) => {
    if (screen.persona) await login(page, testInfo, screen.persona);
    for (const theme of THEMES) {
      // テーマは Cookie で選ぶ (lib/theme.ts)。サーバーが描く時点で決まる
      await page.context().addCookies([{ name: "theme", value: theme, url: APP_URL }]);
      await openScreen(page, screen);
      await expect(page.locator("html")).toHaveClass(new RegExp(`\\b${theme}\\b`));
      expect.soft(await wcagViolations(page), `${label} (${theme})`).toEqual([]);
    }
  });
}
