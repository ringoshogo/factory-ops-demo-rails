module Contracts
  # 請求書発行（請求 → 購買）。受注側が請求書を確定した。宛先は発注側テナントの購買である。
  # 日付は ISO 8601 の文字列、金額は円の整数の文字列。lines は { purchase_order_line_id, item_name, unit_price, quantity,
  # tax_rate_percent, amount } の配列で、確定した請求書に結んだ明細をすべて運ぶ
  # （docs/architecture/context-map.md「検収と請求の流れ」5・6、docs/architecture/data-model.md「イベントの受け口と冪等キー」）
  InvoiceIssued = Event.define(:invoice_id, :supplier_tenant_id, :buyer_tenant_id, :invoice_number, :period_start, :period_end,
    :issued_on, :subtotal, :tax_total, :total, :lines)
end
