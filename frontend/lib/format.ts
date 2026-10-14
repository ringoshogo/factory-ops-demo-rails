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

/** 合計金額の空の理由。受注は品番照合待ちの明細を、発注は受注確定の前の明細を含むと、API が合計を空で返す。 */
const PENDING_TOTAL = { salesOrder: "照合待ち", purchaseOrder: "確定待ち" } as const;

/**
 * 受注と発注の合計金額 (税抜) の表示。API の totalAmount だけから出し、画面で明細から足さない。
 * 単価の無い明細を 0 として一部の合計を出すと、画面ごとに合計が食い違う。空なら金額の代わりに空の理由を出す。
 */
export function totalAmountText(total: string | null, kind: keyof typeof PENDING_TOTAL): string {
  return total === null ? PENDING_TOTAL[kind] : `${yen(total)} 円`;
}
