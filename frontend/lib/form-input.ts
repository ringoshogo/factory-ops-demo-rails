/**
 * フォームの数の入力。GraphQL の Int に 32 ビットの範囲を超える値や数でない値を送ると、変数の型の変換で拒まれ、
 * 入力の誤りではなくトップレベルのエラーになって、どの欄の誤りかを返せない。そのため送る前に形と Int の範囲を確かめ、
 * 業務の範囲 (数量は 1 以上、締め日は 1〜28 か 31 など) は API の検証に任せる。
 */
export const INT_MIN = -(2 ** 31);
export const INT_MAX = 2 ** 31 - 1;

/** GraphQL の Int に送れる整数。前後の空白は除く。送れなければ null。 */
export function parseInt32(value: string): number | null {
  const text = value.trim();
  if (!/^-?\d+$/.test(text)) return null;
  const n = Number(text);
  return n >= INT_MIN && n <= INT_MAX ? n : null;
}

/** GraphQL の BigInt に送る整数 (金額)。桁は API の上限で確かめるので、形だけを確かめて文字列のまま返す。 */
export function parseIntegerText(value: string): string | null {
  const text = value.trim();
  return /^-?\d+$/.test(text) ? text : null;
}

/** 整数の欄の誤りの文言。 */
export const INTEGER_MESSAGE = `整数（${INT_MIN.toLocaleString("ja-JP")}〜${INT_MAX.toLocaleString("ja-JP")}）で入力してください`;
