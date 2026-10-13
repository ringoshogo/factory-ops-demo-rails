import type { CodegenConfig } from "@graphql-codegen/cli";

// 画面の問い合わせ (graphql/<視点>/<操作名>.graphql) から、操作ごとの TypedDocumentNode を 1 つのファイルに書き出す。
// スキーマは Rails が書き出す根の schema.graphql を読む。スキーマから画面が使うフィールドを消すと、生成し直した型で
// 型検査が落ちるので、スキーマと画面の問い合わせの食い違いが同じ commit の CI で分かる。
const config: CodegenConfig = {
  schema: "../schema.graphql",
  documents: "graphql/**/*.graphql",
  generates: {
    "lib/graphql/generated.ts": {
      // typescript-operations は、操作が使う入力型と enum を自分で書き出す。typescript を併せると同じ型を 2 回書く
      plugins: ["typescript-operations", "typed-document-node"],
      config: {
        // 金額 (BigInt) は Number に直すと 2^53 を超えた値で丸まるので、日付と同じく文字列のまま受ける
        scalars: { BigInt: "string", ISO8601Date: "string", ISO8601DateTime: "string" },
        // 並べ替えの見出しを orderBy の field の値から作るので、enum を実行時にも読める値として書き出す
        enumsAsConst: true,
        avoidOptionals: { field: true, inputValue: false, object: true, defaultValue: false },
        useTypeImports: true,
      },
    },
  },
};

export default config;
