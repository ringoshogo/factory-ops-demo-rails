// Next の設定。ヘッダの値は security-headers.json にだけ置き、ここでは全パスに付ける結線だけを行う。
// {nonce} を含むヘッダはリクエストごとに値が変わるので、proxy.ts が差し替えて配る。ここで配ると、proxy を通らない
// 静的なファイルに、差し込む前の値が壊れた CSP として出る。
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const { headers } = JSON.parse(readFileSync(new URL("./security-headers.json", import.meta.url), "utf8"));

const staticHeaders = headers.filter((h) => !h.value.includes("{nonce}"));

const RAILS_URL = process.env.RAILS_URL ?? "http://127.0.0.1:3000";

// ログインの画面が、シードと同じアカウントの一覧 (db/seeds/demo_accounts.json) を読む。frontend/ の外のファイルを
// 読み込めるように、ビルドの根をリポジトリの根にする
const REPO_ROOT = fileURLToPath(new URL("..", import.meta.url));

/** @type {import('next').NextConfig} */
const nextConfig = {
  turbopack: { root: REPO_ROOT },
  outputFileTracingRoot: REPO_ROOT,
  async headers() {
    return [{ source: "/(.*)", headers: staticHeaders }];
  },
  // 取り込みのファイルだけは、ブラウザから multipart/form-data で Rails へ送る。同じオリジンの下に出すので、
  // ブラウザは Rails の CORS を要さず、Rails は Origin ヘッダを許可したフロントエンドのオリジンと比べて
  // 他サイトからの送信を拒む (docs/guides/config.md「CSRF を防ぐ前提：CORS を開けない」)
  async rewrites() {
    return [{ source: "/imports/files", destination: `${RAILS_URL}/imports/files` }];
  },
};

export default nextConfig;
