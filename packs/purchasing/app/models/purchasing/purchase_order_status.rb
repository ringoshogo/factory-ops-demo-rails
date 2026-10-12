module Purchasing
  # 発注の状況を、発注の時刻列と購買の中の入荷・検収から優先順で導出する SQL の式
  # （docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」、docs/adr/010-状況の導出をSQLの式1つにする.md）。
  # 公開 API の表示・絞り込み・件数が、この式だけを読む
  module PurchaseOrderStatus
    # 導出の優先順に並べた 7 つの状況
    ALL = %i[supplier_cancelled cancelled inspected inbound accepted awaiting_supplier_confirmation sent].freeze

    def self.expression
      orders = PurchaseOrder.arel_table
      inbound = InboundShipment.where(InboundShipment.arel_table[:purchase_order_id].eq(orders[:id]))

      Arel::Nodes::Case.new
        .when(orders[:supplier_cancelled_at].not_eq(nil)).then("supplier_cancelled")
        .when(orders[:cancelled_at].not_eq(nil)).then("cancelled")
        .when(inbound.joins(:inspection).arel.exists).then("inspected")
        .when(inbound.arel.exists).then("inbound")
        .when(orders[:accepted_at].not_eq(nil)).then("accepted")
        .when(orders[:awaiting_match_at].not_eq(nil)).then("awaiting_supplier_confirmation")
        .else("sent")
    end
  end
end
