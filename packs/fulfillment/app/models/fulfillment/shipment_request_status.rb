module Fulfillment
  # 出荷依頼の状況を、出荷依頼の時刻列と、出荷停止・出荷指示・出荷実績から優先順で導出する SQL の式
  # （docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」、docs/adr/010-状況の導出をSQLの式1つにする.md）。
  # 公開 API の表示・絞り込み・件数が、この式だけを読む
  module ShipmentRequestStatus
    # 導出の優先順に並べた 5 つの状況
    ALL = %i[cancelled shipped on_hold instructed ready].freeze
    # 状況で並べるときの業務の進み順。導出の優先順（ALL）とは別の一覧で、同じ状況の集まりを持つ
    SORT_ORDER = %i[ready instructed on_hold shipped cancelled].freeze

    # 出荷指示と出荷実績は、所有テナントと出荷依頼の組の外部キーで出荷依頼と同じテナントに限られる。
    # 出荷停止は受注の ID を参照するだけで外部キーが無いので、所有テナントも出荷依頼にそろえ、他社の行を RLS に任せずに除く
    def self.expression
      requests = ShipmentRequest.arel_table
      shipped = Shipment.where(Shipment.arel_table[:shipment_request_id].eq(requests[:id]))
      held = ShippingHold.active.where(ShippingHold.arel_table[:sales_order_id].eq(requests[:sales_order_id])
        .and(ShippingHold.arel_table[:owner_tenant_id].eq(requests[:owner_tenant_id])))
      instructed = ShippingInstruction.active.where(ShippingInstruction.arel_table[:shipment_request_id].eq(requests[:id]))

      Arel::Nodes::Case.new
        .when(requests[:cancelled_at].not_eq(nil)).then("cancelled")
        .when(shipped.arel.exists).then("shipped")
        .when(held.arel.exists).then("on_hold")
        .when(instructed.arel.exists).then("instructed")
        .else("ready")
    end
  end
end
