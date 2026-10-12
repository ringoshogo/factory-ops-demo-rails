import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

// Next のデータのキャッシュを使わない。"use cache" と unstable_cache は関数の引数を鍵にし、セッションの Cookie を鍵に
// 含めないので、あるテナントへの応答を別のテナントに返す。fetch のキャッシュは鍵に要求のヘッダを含めるが、書き込みの後の
// 画面に古い値を出す。画面はどれもセッションごとに Rails を呼び直すので、キャッシュを書く形を書いた時点で落とす
const NO_CACHE = "Next のデータのキャッシュは使わない。セッションを鍵に含めないキャッシュは、別のテナントに応答を返す";
const NO_LINK = "@/components/app-link の Link を使う (先読みしない)";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  {
    rules: {
      "no-restricted-imports": [
        "error",
        {
          paths: [
            { name: "next/link", message: NO_LINK },
            { name: "next/cache", importNames: ["unstable_cache", "cacheLife", "cacheTag"], message: NO_CACHE },
          ],
          // 内部パス経由の Link も止める
          patterns: [{ group: ["next/dist/client/*link*", "next/dist/client/**/link*"], message: NO_LINK }],
        },
      ],
      "no-restricted-syntax": [
        "error",
        { selector: "ExpressionStatement[directive=/^use cache/]", message: NO_CACHE },
        { selector: "CallExpression[callee.name='fetch'] Property[key.name='next']", message: NO_CACHE },
        {
          selector: "ExportNamedDeclaration VariableDeclarator[id.name=/^(revalidate|dynamic|fetchCache)$/]",
          message: NO_CACHE,
        },
      ],
      // Rails を呼ぶのは lib/graphql/request.ts の 1 か所だけにする。呼び出しが散ると、Cookie とエラーの扱いが画面ごとに分かれる
      "no-restricted-globals": [
        "error",
        { name: "fetch", message: "Rails は lib/graphql/request.ts から呼ぶ" },
      ],
    },
  },
  {
    files: ["components/app-link.tsx"],
    rules: { "no-restricted-imports": "off" },
  },
  {
    // 呼び出し口と、ブラウザから同じオリジンの /imports/files へファイルを送る部品だけが fetch を使う
    files: ["lib/graphql/request.ts", "components/import-upload.tsx"],
    rules: { "no-restricted-globals": "off" },
  },
  globalIgnores([
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
    // codegen の生成物。npm run codegen:check が生成し直したものとの一致で守る
    "lib/graphql/generated.ts",
    // Playwright の実行結果
    "test-results/**",
    "playwright-report/**",
  ]),
]);

export default eslintConfig;
