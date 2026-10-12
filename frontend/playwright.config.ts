import { defineConfig, devices } from "@playwright/test";

const STUB_API_PORT = Number(process.env.STUB_PORT ?? 8787);
const STUB_APP_PORT = Number(process.env.STUB_APP_PORT ?? 3100);
// 8080 は Docker Desktop 等が握っていることがある。実測で衝突したので避ける
// (別プロセスが応答すると webServer の起動確認だけ通り、テストは
//  そのプロセスに当たって落ちる)
const LIVE_API_PORT = Number(process.env.LIVE_API_PORT ?? 8091);
const LIVE_APP_PORT = Number(process.env.LIVE_APP_PORT ?? 3101);
// 業務 API は 32文字未満の Proxy-Key を拒否して起動を中止する (T-34a の fail-closed)。
// 短い値にすると API が上がらず、原因が「404」として見える
const PROXY_KEY = "e2e-proxy-key-0123456789abcdef0123";

// 業務 API (Go) が使う接続情報。pgx は DATABASE_URL が空なら PG* を読む。
const PG = {
  PGHOST: process.env.PGHOST ?? "127.0.0.1",
  PGPORT: process.env.PGPORT ?? "5432",
  PGUSER: process.env.PGUSER ?? process.env.USER ?? "postgres",
  PGPASSWORD: process.env.PGPASSWORD ?? "",
  PGDATABASE: process.env.E2E_PGDATABASE ?? "factory_ops_e2e",
};

// 測る対象を2系統に分ける。
//
// - stub: 画面状態の総当たり (T-26)。「API 不達 (3秒)」「混雑中」は
//   実バックエンドでは決定的に作れないので、応答を選べるスタブに当てる
// - live: セッション開始 (T-27)。冪等性はスタブに当てても意味が無いので、
//   本番と同じ Go プロセス + PostgreSQL に当てる
//
// Next のサーバーは向き先 (API_BASE_URL) が起動時に決まるので、2系統ぶん立てる。
// ビルドは npm script 側で1回だけ行う (webServer ごとにビルドすると衝突する)。
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  reporter: process.env.CI ? "github" : "list",
  use: { trace: "on-first-retry" },

  projects: [
    {
      name: "stub",
      // ディレクトリで分ける。ファイル名の列挙だと、タスクが増えるたびに
      // ここを直す必要があり、直し忘れたテストが**黙って走らない**
      testMatch: /e2e\/stub\/.*\.spec\.ts/,
      use: { ...devices["Desktop Chrome"], baseURL: `http://127.0.0.1:${STUB_APP_PORT}` },
    },
    {
      name: "live",
      testMatch: /e2e\/live\/.*\.spec\.ts/,
      use: { ...devices["Desktop Chrome"], baseURL: `http://127.0.0.1:${LIVE_APP_PORT}` },
    },
  ],

  webServer: [
    {
      command: "node e2e/stub-api.mjs",
      env: { STUB_PORT: String(STUB_API_PORT), DEMO_PROXY_KEY: PROXY_KEY },
      url: `http://127.0.0.1:${STUB_API_PORT}/__ready`,
      reuseExistingServer: !process.env.CI,
    },
    {
      command: `npx next start --port ${STUB_APP_PORT}`,
      env: {
        API_BASE_URL: `http://127.0.0.1:${STUB_API_PORT}`,
        DEMO_PROXY_KEY: PROXY_KEY,
      },
      url: `http://127.0.0.1:${STUB_APP_PORT}`,
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
    },
    {
      command: "sh e2e/start-api.sh",
      env: { ...PG, DEMO_PROXY_KEY: PROXY_KEY, PORT: String(LIVE_API_PORT) },
      // /healthz は DB を見ないので、起動しただけで 200 になる
      url: `http://127.0.0.1:${LIVE_API_PORT}/healthz`,
      // **使い回さない**。起動時にセッションを空にするので、残っている
      // プロセスを再利用すると初期化が走らず、上限に達したまま実行される
      reuseExistingServer: false,
      timeout: 240_000,
    },
    {
      command: `npx next start --port ${LIVE_APP_PORT}`,
      env: {
        API_BASE_URL: `http://127.0.0.1:${LIVE_API_PORT}`,
        DEMO_PROXY_KEY: PROXY_KEY,
      },
      url: `http://127.0.0.1:${LIVE_APP_PORT}`,
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
    },
  ],
});
