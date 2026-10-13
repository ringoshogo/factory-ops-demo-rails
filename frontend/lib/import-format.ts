import type { ImportKind } from "@/lib/graphql/generated";

/**
 * 取り込みの CSV の 1 行目に並べる列名。Rails の Imports::CsvFormat::COLUMNS と同じ並びで、画面の説明にだけ使う。
 * 見出しの照合は Rails が行い、違えば取り込み全体を失敗にする。
 */
export const CSV_COLUMNS: Record<ImportKind, readonly { name: string; note: string }[]> = {
  ITEMS: [
    { name: "code", note: "品目コード" },
    { name: "name", note: "品目名" },
    { name: "unit", note: "単位" },
    { name: "tax_rate_percent", note: "税率（8 か 10）" },
    { name: "published", note: "カタログに公開するか（true・false）" },
    { name: "unit_price", note: "販売単価（既存の品目は空なら変えない。新しい品目は必須）" },
    { name: "price_effective_on", note: "単価の改定日（YYYY-MM-DD、今日以降。空なら今日）" },
  ],
  STOCKS: [
    { name: "item_code", note: "品目コード" },
    { name: "quantity", note: "現在庫の数（この数にそろえ、差を移動履歴に残す）" },
  ],
};
