import { readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { expect, type Page } from "@playwright/test";
import type { Persona } from "./world";

/**
 * 寸法とそろえを測る画面の一覧。画面は app/ の全部のルートのグループの page.tsx のファイルから集め、手で並べない。
 * 足した画面が測られないまま通らないように、集めた画面に下の表の行が無ければ落ちる (screenPlans)。
 *
 * 表の行は、その画面を開く役 (受注側の画面は受注側の管理者、発注側の画面は全権限の付与がある発注側の管理者。
 * ログインの画面は役を持たず、ログインせずに開く) と、動的な [id] を決める一覧の画面 (その一覧の最初の行のリンクを開く)、
 * 同じ画面のタブの変種を持つ。
 */
type Plan = { persona?: Persona; from?: string; variants?: string[] };

const PLANS: Record<string, Plan> = {
  "/": {},
  "/settings": { persona: "supplier_admin" },
  "/audit-logs": { persona: "supplier_admin" },
  "/missing": { persona: "supplier_admin" },
  "/supplier/dashboard": { persona: "supplier_admin" },
  "/supplier/sales-orders": { persona: "supplier_admin" },
  "/supplier/sales-orders/[id]": { persona: "supplier_admin", from: "/supplier/sales-orders" },
  "/supplier/part-mappings": { persona: "supplier_admin" },
  "/supplier/stocks": { persona: "supplier_admin", variants: ["", "?tab=movements"] },
  "/supplier/shipment-requests": { persona: "supplier_admin" },
  "/supplier/items": { persona: "supplier_admin" },
  "/supplier/items/[id]": { persona: "supplier_admin", from: "/supplier/items" },
  "/supplier/partnerships": { persona: "supplier_admin" },
  "/supplier/billing": { persona: "supplier_admin" },
  "/supplier/invoices": { persona: "supplier_admin" },
  "/supplier/invoices/[id]": { persona: "supplier_admin", from: "/supplier/invoices" },
  "/supplier/imports": { persona: "supplier_admin" },
  "/supplier/imports/[id]": { persona: "supplier_admin", from: "/supplier/imports" },
  "/buyer/suppliers": { persona: "granted_buyer_admin" },
  "/buyer/purchase-orders": { persona: "granted_buyer_admin" },
  "/buyer/purchase-orders/new": { persona: "granted_buyer_admin" },
  "/buyer/purchase-orders/[id]": { persona: "granted_buyer_admin", from: "/buyer/purchase-orders" },
  "/buyer/received-invoices": { persona: "granted_buyer_admin" },
  "/buyer/received-invoices/[id]": { persona: "granted_buyer_admin", from: "/buyer/received-invoices" },
};

const APP_DIR = join(process.cwd(), "app");

/** app/ の page.tsx から作った画面の道 (/supplier/items/[id] の形)。ルートのグループ ((app)・(entry)) は道に入れない。 */
export function screenRoutes(dir = APP_DIR): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return screenRoutes(path);
    if (name !== "page.tsx") return [];
    const route = `/${relative(APP_DIR, dir).split("/").filter((s) => !/^\(.*\)$/.test(s)).join("/")}`;
    return [route];
  }).sort();
}

export type Screen = { route: string; persona?: Persona; from?: string; variant: string };

/** 測る画面と変種。表に行の無い画面と、画面の無い表の行があれば、ここで落ちる。 */
export function screenPlans(): Screen[] {
  const routes = screenRoutes();
  expect(routes.filter((r) => !PLANS[r]), "測る画面の表に行の無い画面").toEqual([]);
  expect(Object.keys(PLANS).filter((r) => !routes.includes(r)), "画面の無い表の行").toEqual([]);
  return routes.flatMap((route) =>
    (PLANS[route].variants ?? [""]).map((variant) => ({ route, ...PLANS[route], variant })),
  );
}

/** 画面の名前 (スクリーンショットのファイル名に使う)。 */
export const screenName = (s: Screen) =>
  `${s.route.replace(/^\//, "").replace(/[/[\]]+/g, "_").replace(/_+$/, "") || "login"}${s.variant.replace(/[?=&]/g, "_")}`;

/** 画面を開く。動的な [id] は、一覧の画面の最初の行のリンクから決める。 */
export async function openScreen(page: Page, s: Screen): Promise<void> {
  let path = s.route;
  if (s.from) {
    await page.goto(s.from);
    const prefix = s.route.replace("/[id]", "/");
    const link = page.locator(`main a[href^="${prefix}"]`).filter({ hasNot: page.locator("[href$='/new']") });
    const href = await link.evaluateAll((as, p) =>
      as.map((a) => (a as HTMLAnchorElement).pathname).find((h) => h.startsWith(p) && h.length > p.length && !h.endsWith("/new")),
      prefix,
    );
    expect(href, `${s.route}: ${s.from} に詳細へのリンクがある`).toBeTruthy();
    path = href!;
  }
  await page.goto(`${path}${s.variant}`);
  await settle(page);
}

/** 寸法は、Web フォントの読み込みとアニメーション・色の遷移が終わってから測る。 */
export async function settle(page: Page): Promise<void> {
  await page.evaluate(async () => {
    await document.fonts.ready;
    await Promise.all(document.getAnimations().map((a) => a.finished.catch(() => undefined)));
  });
}
