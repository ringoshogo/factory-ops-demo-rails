import { expect, test, type Page } from "@playwright/test";
import { openScreen, screenPlans, settle } from "./support/screens";
import { expectTablesAligned, FIT_WIDTHS } from "./support/table-align";
import { login } from "./support/world";

// 同じ種類の要素の寸法・そろえ・はみ出しを、全画面について測る。測る画面は app/(app) の page.tsx から集める
// (e2e/support/screens.ts)。中身の違うデータ (最も長い品目名と取引先名、ボタンのある行と無い行、状況の全値) は
// E2E の世界 (DemoWorld の variant: :e2e) が持つ

const WIDTHS = [1280, 1024, 390];

async function expectNoPageOverflow(page: Page, at: string) {
  const { scroll, client } = await page.evaluate(() => ({
    scroll: document.documentElement.scrollWidth,
    client: document.documentElement.clientWidth,
  }));
  expect.soft(scroll, `${at}: ページが横にはみ出さない (scrollWidth ${scroll} / clientWidth ${client})`).toBeLessThanOrEqual(client);
}

/** かんばんのカードは、列をまたいで高さがそろい、中身がカードの幅からはみ出さない。 */
async function expectKanbanCards(page: Page, at: string) {
  // 長い名前は末尾を省略して収める (省略した要素の scrollWidth は中身の幅なので数えない)。カード自身が横に
  // スクロールするか、中の要素がカードの右端を越えれば、はみ出している
  const cards = await page.getByTestId("kanban-card").evaluateAll((els) =>
    els.map((el) => ({
      height: Math.round(el.getBoundingClientRect().height),
      overflow: el.scrollWidth > el.clientWidth + 1,
      wider: [...el.querySelectorAll("*")].some((c) => c.getBoundingClientRect().right > el.getBoundingClientRect().right + 1),
    })),
  );
  if (cards.length === 0) return;
  expect.soft([...new Set(cards.map((c) => c.height))], `${at}: かんばんのカードの高さがそろう`).toHaveLength(1);
  expect.soft(cards.filter((c) => c.overflow || c.wider).length, `${at}: カードの中身がはみ出さない`).toBe(0);
}

for (const screen of screenPlans()) {
  const label = `${screen.route}${screen.variant}`;
  test(`${label}: 1280・1024・390 で、はみ出さず、表の見出しとセルがそろう`, async ({ page }, testInfo) => {
    await login(page, testInfo, screen.persona);
    for (const width of WIDTHS) {
      await page.setViewportSize({ width, height: 900 });
      await openScreen(page, screen);
      await expect(page.locator("main h1").first()).toBeVisible();
      await settle(page);
      const at = `${label} @${width}`;
      await expectNoPageOverflow(page, at);
      if (width === 390) continue;
      await expectTablesAligned(page, at, FIT_WIDTHS.includes(width));
      await expectKanbanCards(page, at);
    }
  });
}
