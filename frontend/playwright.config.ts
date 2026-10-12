import { defineConfig, devices } from "@playwright/test";

// E2E は Rails・bin/jobs・Next を起こして当てる 1 系統にする。API に届かない画面は、届かない URL を向いた
// Next をもう 1 つ立てて作る。ポートは手元の開発のサーバー (Rails 3000・Next 3001) と分ける
const RAILS_PORT = 3200;
const APP_PORT = 3201;
const UNREACHABLE_APP_PORT = 3202;
// 誰も待ち受けない番号 (discard)。接続はすぐに拒まれ、request.ts は「API に届かない」に分ける
const UNREACHABLE_RAILS_URL = "http://127.0.0.1:9";

// ワーカーごとに世界を 1 組作る (lib/e2e_prepare.rb)。数を変えるときは E2E_WORKERS で両方に同じ値を渡す
export const WORKERS = Number(process.env.E2E_WORKERS ?? 2);

export const APP_URL = `http://127.0.0.1:${APP_PORT}`;
export const UNREACHABLE_APP_URL = `http://127.0.0.1:${UNREACHABLE_APP_PORT}`;

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  workers: WORKERS,
  forbidOnly: !!process.env.CI,
  // 1 回だけ落ちたテストを再実行で緑にして流さない。落ちたら再現率を測り、待ち方の誤りか製品の競合かを分ける
  retries: 0,
  reporter: process.env.CI ? [["github"], ["list"]] : "list",
  timeout: 60_000,
  use: {
    baseURL: APP_URL,
    trace: "retain-on-failure",
    // 手元ではホストの Chrome を使い (PLAYWRIGHT_CHANNEL=chrome)、Playwright のブラウザを入れずに流せる。
    // CI は npx playwright install が入れた chromium を使う
    channel: process.env.PLAYWRIGHT_CHANNEL || undefined,
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"], channel: process.env.PLAYWRIGHT_CHANNEL || undefined } }],
  webServer: [
    {
      command: "sh e2e/start-rails.sh",
      env: {
        E2E_WORKERS: String(WORKERS),
        E2E_RAILS_PORT: String(RAILS_PORT),
        // rspec のテスト DB と分ける。準備は DB を作り直す
        TEST_DATABASE: process.env.E2E_DATABASE ?? "factory_ops_e2e",
        // 取り込みのファイルの受け口は、ブラウザの Origin をフロントエンドのオリジンと比べる
        FRONTEND_ORIGIN: APP_URL,
      },
      url: `http://127.0.0.1:${RAILS_PORT}/up`,
      // 既定の SIGKILL では bin/jobs が Solid Queue の登録を消さずに終わり、次の実行の e2e:check が心拍の途絶えるまで止まる。
      // SIGTERM で止め、登録を消させる
      gracefulShutdown: { signal: "SIGTERM", timeout: 15_000 },
      // 使い回さない。前の実行の世界を残したまま流すと、テストが前の実行の書き込みを見る
      reuseExistingServer: false,
      timeout: 300_000,
      stdout: "pipe",
    },
    {
      command: `npx next start --port ${APP_PORT}`,
      env: { RAILS_URL: `http://127.0.0.1:${RAILS_PORT}` },
      url: APP_URL,
      reuseExistingServer: false,
      timeout: 120_000,
    },
    {
      command: `npx next start --port ${UNREACHABLE_APP_PORT}`,
      env: { RAILS_URL: UNREACHABLE_RAILS_URL },
      url: UNREACHABLE_APP_URL,
      reuseExistingServer: false,
      timeout: 120_000,
    },
  ],
});
