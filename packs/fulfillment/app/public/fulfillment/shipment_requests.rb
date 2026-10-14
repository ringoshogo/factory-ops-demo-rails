module Fulfillment
  # 受注側が自社の出荷依頼と、その出荷指示・出荷実績を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）。
  # *_for は親の ID の配列を取り、ID ごとの値のハッシュを返す
  module ShipmentRequests
    # order_by は { field:, direction: } の配列で、1 つ目の列から順に並べる。空なら作った順の新しいものから並べる。
    # filter は状況で絞る。状況の空の配列は 0 件で、nil なら絞らない
    def self.list(actor, first:, after:, order_by: [], filter: {})
      Page.of(filtered(Scope.call(actor, ShipmentRequest.all), **filter), first:, after:, sort: Page::Sort.of(order_by, order_columns(actor)),
        columns: [ ShipmentRequestStatus.expression.as("status") ]) { to_values(_1) }
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.find(actor, id)
      to_values(with_status(Scope.call(actor, ShipmentRequest.where(id:)))).first
    end

    # 受注 ID ごとの出荷依頼。出荷可能になる前の受注は含まない
    def self.for_sales_orders(actor, sales_order_ids)
      to_values(with_status(Scope.call(actor, ShipmentRequest.where(sales_order_id: sales_order_ids)))).index_by(&:sales_order_id)
    end

    DUE_WITHIN_LIMIT = 100

    # 出荷も取消もしていない出荷依頼（出荷待ち・出荷指示済・出荷停止中）のうち、期限が today から days 日後以下のもの。
    # 期限を過ぎたものも含め、期限の昇順で上限の件数まで返す。期限の無い出荷依頼は返さない。
    # 状況は一覧の絞り込みと同じ式で絞り、ダッシュボードと、そこから飛ぶ一覧の状況が食い違わないようにする
    def self.due_within(actor, today:, days:)
      requests = filtered(Scope.call(actor, ShipmentRequest.where(due_date: ..today + days)), statuses: %i[ready instructed on_hold])
      to_values(with_status(requests.order(:due_date, :id).limit(DUE_WITHIN_LIMIT)))
    end

    def self.lines_for(actor, request_ids)
      lines = Scope.call(actor, ShipmentRequestLine.where(shipment_request_id: request_ids)).order(:id).map { to_value(ShipmentRequestLineValue, _1) }
      request_ids.index_with { [] }.merge(lines.group_by(&:shipment_request_id))
    end

    # 明細 ID ごとの出荷依頼の明細
    def self.request_lines(actor, line_ids)
      Scope.call(actor, ShipmentRequestLine.where(id: line_ids)).to_h { [ _1.id, to_value(ShipmentRequestLineValue, _1) ] }
    end

    # 出荷依頼 ID ごとの有効な出荷指示。無ければ含まない
    def self.instructions_for(actor, request_ids)
      Scope.call(actor, ShippingInstruction.active.where(shipment_request_id: request_ids))
        .to_h { [ _1.shipment_request_id, to_value(ShippingInstructionValue, _1) ] }
    end

    def self.shipments_for(actor, request_ids)
      Scope.call(actor, Shipment.where(shipment_request_id: request_ids)).to_h { [ _1.shipment_request_id, to_value(ShipmentValue, _1) ] }
    end

    def self.shipment_lines_for(actor, shipment_ids)
      lines = Scope.call(actor, ShipmentLine.where(shipment_id: shipment_ids)).order(:id).map { to_value(ShipmentLineValue, _1) }
      shipment_ids.index_with { [] }.merge(lines.group_by(&:shipment_id))
    end

    # statuses の空の配列は、Arel の In が 1=0 にするので 0 件になる（activerecord 8.1 の Arel::Visitors::ToSql#visit_Arel_Nodes_In）
    def self.filtered(relation, statuses: nil)
      statuses.nil? ? relation : relation.where(ShipmentRequestStatus.expression.in(statuses.map(&:to_s)))
    end

    # 並べてよい列（docs/architecture/graphql-schema.md「ページングと N+1」）。
    # 得意先の名前は取引関係の公開 API の副問い合わせから引き、状況は業務の進み順の位置で並べる
    def self.order_columns(actor)
      requests = ShipmentRequest.arel_table
      { due_date: [ requests[:due_date], :date ],
        customer_name: [ Partnerships::Directory.tenant_names_sql(actor).lookup(:name, :tenant_id, requests[:buyer_tenant_id]), :string ],
        status: [ Page::Sort.rank(ShipmentRequestStatus.expression, ShipmentRequestStatus::SORT_ORDER), :integer ] }
    end

    def self.with_status(relation) = relation.select(ShipmentRequest.arel_table[Arel.star], ShipmentRequestStatus.expression.as("status"))

    # requests は状況の式を status の別名で読んだ出荷依頼
    def self.to_values(requests)
      requests.map do |request|
        ShipmentRequestValue.new(id: request.id, owner_tenant_id: request.owner_tenant_id, sales_order_id: request.sales_order_id,
          buyer_tenant_id: request.buyer_tenant_id, due_date: request.due_date, status: request["status"].to_sym)
      end
    end

    def self.to_value(klass, record) = klass.new(**record.slice(*klass.members.map(&:to_s)).symbolize_keys)
    private_class_method :order_columns, :filtered, :with_status, :to_values, :to_value
  end
end
