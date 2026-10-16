module Fulfillment
  # 受注からの「出荷可能」の受け手。受注側テナントの名義で、自社の出荷依頼だけを書く
  # （docs/architecture/data-model.md「イベントの受け口と冪等キー」）。取引関係の状態は見ない。
  # 同じテナントの中で受注から出荷へ渡るのは、このイベントだけである。受注が出荷を呼ぶと受注が出荷に依存し、出荷が受注を読む向きと循環するからで、
  # 取消の後に届いて出荷依頼ができても、状況は受注から導出して取消済になる（docs/adr/012-同じテナントの中の連結を同期にし出荷可能だけをイベントで残す.md）。
  # イベントの受け手は操作者のいない入口なので、テナントの設定を求め、所有の条件を RLS に任せずに書き、値を返さない
  # （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
  module SalesEventReceiver
    def self.handle(event)
      Tenancy.require_tenant!
      case event
      when Contracts::SalesOrderReadyForShipment then create_request(event)
      else raise ArgumentError, "unexpected event: #{event.class}"
      end
      nil
    end

    # 「出荷可能」の写しを作る。冪等キーは sales_order_id で、2 回目の配送では何もしない。同時に届いた配送は一意索引が止める。
    # 受注番号は受注を作った後に変わらないので、写した後に書き直さない。受注番号を運ぶ前に登録したイベントは空を写し、
    # 作り直しのタスク（bin/rails read_models:rebuild）が埋める
    def self.create_request(event)
      return if ShipmentRequest.exists?(owner_tenant_id: Current.tenant_id, sales_order_id: event.sales_order_id)

      ShipmentRequest.transaction(requires_new: true) do
        ShipmentRequest.create!(
          owner_tenant_id: Current.tenant_id,
          sales_order_id: event.sales_order_id,
          sales_order_no: event.sales_order_no,
          buyer_tenant_id: event.buyer_tenant_id,
          source_purchase_order_id: event.purchase_order_id,
          due_date: event.due_date&.then { Date.iso8601(_1) },
          lines: event.lines.map do |line|
            ShipmentRequestLine.new(owner_tenant_id: Current.tenant_id, sales_order_line_id: line.fetch("sales_order_line_id"),
              source_purchase_order_line_id: line.fetch("purchase_order_line_id"), item_id: line.fetch("item_id"),
              quantity: line.fetch("quantity"))
          end
        )
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    end
    private_class_method :create_request
  end
end
