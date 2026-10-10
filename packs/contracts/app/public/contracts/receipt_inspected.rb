module Contracts
  # 検収完了（購買 → 受注）。発注側が入荷 1 件を検収した。shipment_id は入荷の元の出荷実績の ID、inspected_on は ISO 8601 の日付の文字列。
  # lines は { purchase_order_line_id, accepted_quantity } の配列で、入荷の全明細を運ぶ（docs/architecture/data-model.md「イベントの受け口と冪等キー」）
  ReceiptInspected = Event.define(:shipment_id, :purchase_order_id, :buyer_tenant_id, :supplier_tenant_id, :inspected_on, :lines)
end
