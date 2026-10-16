import { readFileSync } from "node:fs";
import { join } from "node:path";
import { expect, type Page, type TestInfo } from "@playwright/test";

/**
 * E2E の世界のアカウント。bin/rails e2e:prepare が、Playwright のワーカーごとに世界を 1 組作って
 * tmp/e2e/worlds.json に書く (lib/e2e_prepare.rb)。テストは自分のワーカーの世界のアカウントだけでログインし、
 * 他の世界に書かない。ワーカーの番号は parallelIndex (0 からワーカーの数 - 1。落ちて作り直したワーカーも同じ番号を継ぐ)。
 */
export type Persona =
  | "supplier_admin"
  | "supplier_member"
  | "granted_buyer_admin"
  | "granted_buyer_member"
  | "revoked_buyer_admin"
  | "revoked_buyer_member";

type Account = { persona: Persona; tenant: string; role: string; name: string; email: string; password: string };
type World = { index: number; accounts: Account[] };

// Playwright は frontend/ を作業の場所にして動く
const WORLDS_PATH = join(process.cwd(), "../tmp/e2e/worlds.json");

export function account(testInfo: TestInfo, persona: Persona): Account {
  const worlds: World[] = JSON.parse(readFileSync(WORLDS_PATH, "utf8"));
  const world = worlds.find((w) => w.index === testInfo.parallelIndex);
  if (!world) throw new Error(`ワーカー ${testInfo.parallelIndex} の世界が無い (e2e:prepare のワーカーの数を確かめる)`);
  return world.accounts.find((a) => a.persona === persona)!;
}

/**
 * ログインの後に移った先の URL を待つ上限 (ミリ秒)。ほかの期待は Playwright の既定の 5 秒のまま。
 * この期待はログインが済んで URL が変わったことを確かめるだけで、製品の競合を待つものではないので、延ばしても製品の遅さを隠さない。
 * 負荷の高い手元では、ワーカーの最初のログインが既定の 5 秒を超えて落ちる
 */
const LOGIN_URL_TIMEOUT = 20_000;

/** ログインの画面から入る。移った先 (受注側のダッシュボードか発注側の発注一覧) に着いたことを確かめてから返す。 */
export async function login(page: Page, testInfo: TestInfo, persona: Persona): Promise<Account> {
  const user = account(testInfo, persona);
  await page.goto("/");
  await page.getByLabel("メールアドレス").fill(user.email);
  await page.getByLabel("パスワード").fill(user.password);
  await page.getByRole("button", { name: "ログイン" }).click();
  await expect(page).toHaveURL(/\/(supplier\/dashboard|buyer\/purchase-orders)$/, { timeout: LOGIN_URL_TIMEOUT });
  return user;
}

/** サイドバーのログアウトで出る。ログインの画面に戻ったことを確かめる。 */
export async function logout(page: Page) {
  await page.getByRole("button", { name: "ログアウト" }).first().click();
  await expect(page.getByRole("button", { name: "ログイン" })).toBeVisible();
}
