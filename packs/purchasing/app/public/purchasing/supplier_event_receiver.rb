module Purchasing
  # 受注側からのイベントの受け手。発注側テナントの名義で、自社の発注の時刻列と、明細と入荷の写しと、取消依頼の回答だけを書く
  # （docs/architecture/data-model.md「イベントの受け口と冪等キー」）。取引関係の状態は見ない。
  # 時刻列には、受け取った時刻ではなく、イベントが運ぶ受注側の発生の時刻を書く。配送が遅れても、発注側で後から起きた出来事と
  # 前後が入れ替わらない。
  # イベントの受け手は操作者のいない入口なので、テナントの設定を求め、所有の条件を RLS に任せずに書き、値を返さない
  # （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
  module SupplierEventReceiver
    def self.handle(event)
      Tenancy.require_tenant!
      order = PurchaseOrder.lock.find_by!(owner_tenant_id: Current.tenant_id, id: event.purchase_order_id,
        supplier_tenant_id: event.supplier_tenant_id)

      case event
      when Contracts::SalesOrderConfirmed then accept(order, event)
      when Contracts::PartMatchPending then order.update!(awaiting_match_at: occurred_at(event)) unless order.awaiting_match_at
      when Contracts::ShipmentPosted then receive_shipment(order, event)
      when Contracts::CancellationApproved then answer_cancellation(order, event, "approved")
      when Contracts::CancellationRejected then answer_cancellation(order, event, "rejected")
      # cancelled_at は見ない。受注側は審査中と承認済みの受注の取消を CONFLICT にするので、2 つの取消の時刻は並ばない。
      # 並べば CHECK 制約で失敗し、再配送でも直らないので、受け手で片方を捨てずに失敗で知らせる
      when Contracts::SalesOrderCancelled then order.update!(supplier_cancelled_at: occurred_at(event)) unless order.supplier_cancelled_at
      else raise ArgumentError, "unexpected event: #{event.class}"
      end
      nil
    end

    # 確定した品目名と単価を明細に写す。accepted_at が空のときだけ書く
    def self.accept(order, event)
      return if order.accepted_at

      confirmed = event.lines.index_by { _1.fetch("purchase_order_line_id") }
      order.lines.each do |line|
        values = confirmed.fetch(line.id)
        line.update!(confirmed_item_name: values.fetch("item_name"), confirmed_unit_price: Integer(values.fetch("unit_price")))
      end
      order.update!(accepted_at: occurred_at(event))
    end

    # 取消依頼に回答を記録する。回答が空のときだけ書き、承認なら発注を取消済みにする。却下は回答の記録だけで、
    # 発注は依頼の前の状況に戻る（docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）
    def self.answer_cancellation(order, event, outcome)
      request = order.cancellation_requests.lock.find(event.cancellation_request_id)
      return if request.outcome

      decided_at = occurred_at(event)
      request.update!(outcome:, decided_at:)
      order.update!(cancelled_at: decided_at) if outcome == "approved"
    end

    # 発生の時刻を運ぶ前に登録したジョブのペイロードは occurred_at を持たないので、そのときだけ受け取った時刻にする
    def self.occurred_at(event) = event.occurred_at ? Time.iso8601(event.occurred_at) : Time.current

    # 「出荷計上」を入荷として写す。冪等キーは shipment_id で、発注の行ロックが同じ出荷の配送を直列にする。
    # 受注 ID と受注明細 ID は保存しない
    def self.receive_shipment(order, event)
      return if InboundShipment.exists?(owner_tenant_id: Current.tenant_id, shipment_id: event.shipment_id)

      lines = order.lines.index_by(&:id)
      order.inbound_shipments.create!(owner_tenant_id: order.owner_tenant_id, shipment_id: event.shipment_id,
        shipped_on: Date.iso8601(event.shipped_on),
        lines: event.lines.map do |line|
          InboundShipmentLine.new(owner_tenant_id: order.owner_tenant_id,
            purchase_order_line: lines.fetch(line.fetch("purchase_order_line_id")), shipped_quantity: line.fetch("quantity"))
        end)
    end
    private_class_method :accept, :answer_cancellation, :occurred_at, :receive_shipment
  end
end
