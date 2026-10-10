module Contracts
  # 出荷取消（受注 → 出荷）。受注を取り消した。cancellation_review_id は取消を承認した審査で、審査を経ない取消では空。
  # ready_for_shipment は、この受注について「出荷可能」を出したか。出荷は、出したのに出荷依頼がまだ無いときを、
  # 出荷可能より先に届いたと判断する（docs/architecture/data-model.md「イベントの届く順の入れ替わり」）
  ShipmentCancelled = Event.define(:sales_order_id, :supplier_tenant_id, :cancellation_review_id, :ready_for_shipment)
end
