module Contracts
  # 品番照合待ち（受注 → 購買）。照合できない明細が 1 つでもあり、受注を確定できなかった
  PartMatchPending = Event.define(:purchase_order_id, :buyer_tenant_id, :supplier_tenant_id)
end
