module Sales
  # 検収の記録。「検収完了」の写しで、shipment_id は出荷実績への ID 参照。関連を張らない
  class InspectionRecord < TenantRecord
    belongs_to :sales_order_line
  end
end
