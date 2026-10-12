// Next の設定。ヘッダの値は security-headers.json にだけ置き、ここでは全パスに付ける結線だけを行う。
// {nonce} を含むヘッダはリクエストごとに値が変わるので、proxy.ts が差し替えて配る。ここで配ると、proxy を通らない
// 静的なファイルに、差し込む前の値が壊れた CSP として出る。
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const { headers } = JSON.parse(readFileSync(new URL("./security-headers.json", import.meta.url), "utf8"));

const staticHeaders = headers.filter((h) => !h.value.includes("{nonce}"));

// ログインの画面が、シードと同じアカウントの一覧 (db/seeds/demo_accounts.json) を読む。frontend/ の外のファイルを
// 読み込めるように、ビルドの根をリポジトリの根にする
const REPO_ROOT = fileURLToPath(new URL("..", import.meta.url));

/** @type {import('next').NextConfig} */
const nextConfig = {
  // 公開の配置のイメージ (frontend/Dockerfile) だけが NEXT_OUTPUT=standalone を渡し、node_modules を持たないサーバーを組み立てる。
  // 手元と E2E の next start は standalone の出力では動かないと警告するので、渡さないときは既定の出力のままにする
  output: process.env.NEXT_OUTPUT === "standalone" ? "standalone" : undefined,
  turbopack: { root: REPO_ROOT },
  outputFileTracingRoot: REPO_ROOT,
  async headers() {
    return [{ source: "/(.*)", headers: staticHeaders }];
  },
};

export default nextConfig;
