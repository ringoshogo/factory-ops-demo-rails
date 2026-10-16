module Fulfillment
  # 出荷依頼の状況を、受注の取消済と審査中、出荷指示・出荷実績から優先順で導出する SQL の式
  # （docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」、docs/adr/010-状況の導出をSQLの式1つにする.md）。
  # 公開 API の表示・絞り込み・件数が、この式だけを読む
  module ShipmentRequestStatus
    # 導出の優先順に並べた 5 つの状況
    ALL = %i[cancelled shipped on_hold instructed ready].freeze
    # 状況で並べるときの業務の進み順。導出の優先順（ALL）とは別の一覧で、同じ状況の集まりを持つ
    SORT_ORDER = %i[ready instructed on_hold shipped cancelled].freeze

    # 取消済と出荷停止中は、受注の公開 API が操作者の scope を掛けて返す副問い合わせから読む。出荷依頼が見えない受注を指すときは、
    # 副問い合わせに行が無いので、取消済でも出荷停止中でもない側に倒れる。
    # 出荷指示と出荷実績は、所有テナントと出荷依頼の組の外部キーで出荷依頼と同じテナントに限られる
    def self.expression(actor)
      requests = ShipmentRequest.arel_table
      shipped = Shipment.where(Shipment.arel_table[:shipment_request_id].eq(requests[:id]))
      instructed = ShippingInstruction.active.where(ShippingInstruction.arel_table[:shipment_request_id].eq(requests[:id]))

      Arel::Nodes::Case.new
        .when(order_cancelled(actor)).then("cancelled")
        .when(shipped.arel.exists).then("shipped")
        .when(order_flag(actor, :under_review)).then("on_hold")
        .when(instructed.arel.exists).then("instructed")
        .else("ready")
    end

    # 出荷依頼の受注が取消済か。見えない受注は偽になる。取消済の受注の出荷依頼に残った有効な出荷指示を、読む側が除くときにも使う
    def self.order_cancelled(actor) = order_flag(actor, :cancelled)

    def self.order_flag(actor, role)
      Arel::Nodes::NamedFunction.new("COALESCE", [
        Sales::OrderShipping.status_sql(actor).lookup(role, :sales_order_id, ShipmentRequest.arel_table[:sales_order_id]),
        Arel::Nodes::False.new
      ])
    end
    private_class_method :order_flag
  end
end
