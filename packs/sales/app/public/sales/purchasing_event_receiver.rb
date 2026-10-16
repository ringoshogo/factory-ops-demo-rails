module Sales
  # 購買からの「取消依頼」と「検収完了」の受け手（docs/architecture/context-map.md「取消の流れ」2・4、「検収と請求の流れ」2・3）。
  # 受注側テナントの名義で、自社の受注に取消の審査を作って出荷へ「出荷停止」を出すか、検収数量を記録して受注を検収済にし、
  # 請求へ「請求対象確定」を出す。
  # 取引関係の状態は見ない。「発注登録」の受け手は、受注を作る腐敗防止層（PurchaseOrderTranslator）である。
  # イベントの受け手は操作者のいない入口なので、テナントの設定を求め、所有の条件を RLS に任せずに書き、値を返さない
  # （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
  module PurchasingEventReceiver
    # 「検収完了」が、受注側の「出荷計上」より先に届いた。再配送に任せる
    class NotShippedYet < StandardError; end

    def self.handle(event)
      Tenancy.require_tenant!
      case event
      when Contracts::CancellationRequested then review(event)
      when Contracts::ReceiptInspected then inspect_shipment(event)
      else raise ArgumentError, "unexpected event: #{event.class}"
      end
      nil
    end

    # 冪等キーは取消依頼 ID。受注の行ロックが、同じ依頼の配送と審査の決着を直列にする。
    # 受注がまだ無い（発注登録より先に届いた）ときは find_by! で失敗させ、再配送に任せる。
    # 受注が出荷済みか取消済なら、承認できないので、審査を作らずに自動で却下する
    def self.review(event)
      order = SalesOrder.lock.find_by!(owner_tenant_id: Current.tenant_id, source_purchase_order_id: event.purchase_order_id,
        customer_tenant_id: event.buyer_tenant_id)
      return if CancellationReview.exists?(owner_tenant_id: Current.tenant_id, source_cancellation_request_id: event.cancellation_request_id)
      return publish_rejected(order, event) if order.shipped_at || order.cancelled_at

      review = order.cancellation_reviews.create!(owner_tenant_id: order.owner_tenant_id,
        source_cancellation_request_id: event.cancellation_request_id, requested_at: Time.iso8601(event.requested_at))
      Contracts.publish(Contracts::ShippingHeld.new(cancellation_review_id: review.id, sales_order_id: order.id,
        supplier_tenant_id: order.owner_tenant_id))
    end

    # 自動の却下は審査を残さないので、同じ依頼が 2 回届くと 2 回出す。購買の受け手は回答が空のときだけ書くので、結果は変わらない。
    # 決着の時刻の列も無いので、発生の時刻は発行するときの時刻にする
    def self.publish_rejected(order, event)
      Contracts.publish(Contracts::CancellationRejected.new(cancellation_request_id: event.cancellation_request_id,
        purchase_order_id: event.purchase_order_id, buyer_tenant_id: order.customer_tenant_id, supplier_tenant_id: order.owner_tenant_id,
        occurred_at: Time.current.iso8601(6)))
    end
    # 冪等キーは出荷実績 ID と受注明細 ID の組で、受注の行ロックが同じ出荷実績の配送を直列にする。
    # 全明細を同じトランザクションで書くので、書いたかどうかは出荷実績 ID だけで判定する。
    # 分納しないので出荷実績は受注ごとに 1 件で、その検収完了が届けば受注のすべての出荷実績が検収されている。
    # 検収は出荷の後にしか起きないが、受注側の「出荷計上」の配送が遅れると先に届くので、出荷済でなければ失敗させて再配送に任せる。
    # 検収済の時刻だけを先に書くと、出荷済であることを求める CHECK 制約に当たる
    def self.inspect_shipment(event)
      order = SalesOrder.lock.find_by!(owner_tenant_id: Current.tenant_id, source_purchase_order_id: event.purchase_order_id,
        customer_tenant_id: event.buyer_tenant_id)
      return if InspectionRecord.exists?(owner_tenant_id: Current.tenant_id, shipment_id: event.shipment_id)
      raise NotShippedYet, "受注 #{order.id} はまだ出荷済でない" unless order.shipped_at

      lines = order.lines.index_by(&:source_purchase_order_line_id)
      inspected_on = Date.iso8601(event.inspected_on)
      event.lines.each do |line|
        record = InspectionRecord.create!(owner_tenant_id: order.owner_tenant_id, shipment_id: event.shipment_id,
          sales_order_line: lines.fetch(line.fetch("purchase_order_line_id")), quantity: line.fetch("accepted_quantity"), inspected_on:)
        publish_billable(order, record)
      end
      order.update!(inspected_at: Time.current)
    end

    # 検収した受注明細ごとに、受注明細に写した品目名・単価・税率で「請求対象確定」を出す（context-map.md「検収と請求の流れ」3）。
    # 検収数量が 0 の明細は請求する額が無いので出さない。検収の記録と同じトランザクションで出すので、
    # 再配送で記録を書かずに戻るときは、このイベントも出し直さない
    def self.publish_billable(order, record)
      return if record.quantity.zero?

      line = record.sales_order_line
      Contracts.publish(Contracts::BillableItemConfirmed.new(supplier_tenant_id: order.owner_tenant_id,
        buyer_tenant_id: order.customer_tenant_id, shipment_id: record.shipment_id, sales_order_line_id: line.id,
        purchase_order_line_id: line.source_purchase_order_line_id, item_name: line.item_name, unit_price: line.unit_price.to_s,
        tax_rate_percent: line.tax_rate_percent, quantity: record.quantity, inspected_on: record.inspected_on.iso8601))
    end
    private_class_method :review, :publish_rejected, :inspect_shipment, :publish_billable
  end
end
