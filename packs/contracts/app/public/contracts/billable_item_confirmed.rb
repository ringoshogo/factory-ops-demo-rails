module Contracts
  # 請求対象確定（受注 → 請求）。受注側が検収した受注明細 1 つ分で、宛先は同じ受注側テナントの請求である。
  # unit_price は円の整数の文字列、inspected_on は ISO 8601 の日付の文字列
  # （docs/architecture/context-map.md「検収と請求の流れ」3、docs/architecture/data-model.md「イベントの受け口と冪等キー」）
  BillableItemConfirmed = Event.define(:supplier_tenant_id, :buyer_tenant_id, :shipment_id, :sales_order_line_id,
    :purchase_order_line_id, :item_name, :unit_price, :tax_rate_percent, :quantity, :inspected_on)
end
