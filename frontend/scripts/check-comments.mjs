// コードのコメントに、経緯・マイルストーンの番号・台帳の ID・流用元の仕様とタスクの番号を書かせない
// (docs/guides/comments.md「機械で止めるもの」)。Ruby のファイルは RuboCop の Cop が見るので、ここでは frontend/ の
// TypeScript・JavaScript・CSS・GraphQL のコメントを見る。npm run lint から呼ぶ。
//
// 引数にファイルを渡すとそのファイルだけを見る。渡さなければ frontend/ の追跡対象を見る。
import { readdirSync, readFileSync, statSync } from "node:fs";
import { extname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import ts from "typescript";

const ROOT = fileURLToPath(new URL("..", import.meta.url));

// 生成物・依存・ビルドの成果物は見ない
const SKIP_DIRS = new Set(["node_modules", ".next", "test-results", "playwright-report", "out", "build"]);
const SKIP_FILES = new Set(["lib/graphql/generated.ts", "next-env.d.ts"]);
const SCRIPT = new Set([".ts", ".tsx", ".js", ".mjs", ".cjs", ".mts"]);

// 語の前後に英数字が続くもの (M8x30 のような品番、OI-ring) は止めない
const word = (body) => new RegExp(`(?<![A-Za-z0-9_])${body}(?![A-Za-z0-9_])`);

export const RULES = [
  { name: "マイルストーンの番号", pattern: word("M\\d+") },
  { name: "台帳の ID", pattern: word("(?:OI|IB)-\\d+") },
  { name: "流用元のタスクの番号", pattern: word("T-\\d+[a-z]?") },
  { name: "流用元の正本の番号", pattern: word("(?:US|N)-\\d+") },
  { name: "流用元の仕様の節", pattern: /仕様\s*(?:cycle-\d+\s*)?§|§\s*\d/ },
  { name: "流用元の正本・台帳への参照", pattern: /正本\s*[A-Z]|台帳\s*[A-Z]/ },
  { name: "経緯の語", pattern: /以前は|レビューで|指摘で|を直した|当初は/ },
  { name: "予定", pattern: word("(?:TODO|FIXME)") },
];

/** ファイルの中身からコメントを [行番号, 文] の配列で返す。 */
export function commentsOf(path, text) {
  const ext = extname(path);
  if (SCRIPT.has(ext)) return scriptComments(path, text);
  if (ext === ".css") return blockComments(text);
  if (ext === ".graphql") return hashComments(text);
  return [];
}

// 構文木の字句をすべてたどり、字句の前後の空白に付いたコメントを集める。スキャナを先頭から回すだけだと、
// テンプレートリテラルの `${...}` の後を読み違え、その先のコメントを取りこぼす
function scriptComments(path, text) {
  const kind = path.endsWith(".tsx") || path.endsWith(".jsx") ? ts.ScriptKind.TSX : ts.ScriptKind.TS;
  const source = ts.createSourceFile(path, text, ts.ScriptTarget.Latest, true, kind);
  const found = new Map();
  const collect = (ranges) => {
    for (const range of ranges ?? []) found.set(range.pos, [lineOf(text, range.pos), text.slice(range.pos, range.end)]);
  };
  const visit = (node) => {
    // JSX の文字は字句の前の空白ではないので、`//` で始まっていてもコメントとして読まない
    if (node.kind !== ts.SyntaxKind.JsxText) {
      collect(ts.getLeadingCommentRanges(text, node.getFullStart()));
      collect(ts.getTrailingCommentRanges(text, node.getEnd()));
    }
    for (const child of node.getChildren(source)) visit(child);
  };
  visit(source);
  return [...found.entries()].sort(([a], [b]) => a - b).map(([, comment]) => comment);
}

function blockComments(text) {
  return [...text.matchAll(/\/\*[\s\S]*?\*\//g)].map((m) => [lineOf(text, m.index), m[0]]);
}

function hashComments(text) {
  return [...text.matchAll(/#.*$/gm)].map((m) => [lineOf(text, m.index), m[0]]);
}

const lineOf = (text, index) => text.slice(0, index).split("\n").length;

/** コメントが規則に当たれば [規則の名前] を返す。 */
export function violations(comment) {
  return RULES.filter((rule) => rule.pattern.test(comment)).map((rule) => rule.name);
}

function* walk(dir) {
  for (const name of readdirSync(dir)) {
    if (SKIP_DIRS.has(name)) continue;
    const path = join(dir, name);
    if (statSync(path).isDirectory()) yield* walk(path);
    else yield path;
  }
}

function main(argv) {
  const files = argv.length > 0 ? argv : [...walk(ROOT)];
  let failed = 0;
  for (const file of files) {
    const rel = relative(ROOT, file);
    if (SKIP_FILES.has(rel)) continue;
    for (const [line, comment] of commentsOf(file, readFileSync(file, "utf8"))) {
      for (const name of violations(comment)) {
        console.error(`${rel}:${line}: コメントに${name}がある: ${comment.split("\n")[0].trim()}`);
        failed += 1;
      }
    }
  }
  if (failed > 0) {
    console.error(`\nコメントの規約 (docs/guides/comments.md) に当たる箇所が ${failed} 件ある。いまの振る舞いと理由に書き直す`);
    process.exit(1);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
