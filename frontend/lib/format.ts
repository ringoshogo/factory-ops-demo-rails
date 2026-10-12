/**
 * 数値と金額の表示 (3 桁区切り)。サーバー部品とクライアント部品の両方が使う。
 *
 * 金額は API が BigInt を文字列で返すので、Number に直さず BigInt のまま区切る。Number は 2^53 を超えた値を丸める。
 */
export const formatNumber = (n: number) => n.toLocaleString("ja-JP");

/** 金額 (円)。API の BigInt の文字列を受ける。 */
export function yen(amount: string | bigint): string {
  return BigInt(amount).toLocaleString("ja-JP");
}

/** 金額の足し算。API の BigInt の文字列どうしを、BigInt のまま足す。 */
export function sumAmounts(amounts: readonly (string | bigint)[]): bigint {
  return amounts.reduce<bigint>((sum, a) => sum + BigInt(a), BigInt(0));
}
