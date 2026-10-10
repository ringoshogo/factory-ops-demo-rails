module Sales
  # 購買からの「取消依頼」の受け手（docs/architecture/context-map.md「取消の流れ」2・4）。受注側テナントの名義で、
  # 自社の受注に取消の審査を作り、出荷へ「出荷停止」を出す。取引関係の状態は見ない。
  # 「発注登録」の受け手は、受注を作る腐敗防止層（PurchaseOrderTranslator）である
  module PurchasingEventReceiver
    def self.handle(event)
      case event
      when Contracts::CancellationRequested then review(event)
      else raise ArgumentError, "unexpected event: #{event.class}"
      end
    end

    # 冪等キーは取消依頼 ID。受注の行ロックが、同じ依頼の配送と審査の決着を直列にする。
    # 受注がまだ無い（発注登録より先に届いた）ときは find_by! で失敗させ、再配送に任せる。
    # 受注が出荷済みか取消済なら、承認できないので、審査を作らずに自動で却下する
    def self.review(event)
      order = SalesOrder.lock.find_by!(owner_tenant_id: Current.tenant_id, source_purchase_order_id: event.purchase_order_id,
        customer_tenant_id: event.buyer_tenant_id)
      return if CancellationReview.exists?(source_cancellation_request_id: event.cancellation_request_id)
      return publish_rejected(order, event) if order.shipped_at || order.cancelled_at

      review = order.cancellation_reviews.create!(owner_tenant_id: order.owner_tenant_id,
        source_cancellation_request_id: event.cancellation_request_id, requested_at: Time.iso8601(event.requested_at))
      Contracts.publish(Contracts::ShippingHeld.new(cancellation_review_id: review.id, sales_order_id: order.id,
        supplier_tenant_id: order.owner_tenant_id))
    end

    # 自動の却下は審査を残さないので、同じ依頼が 2 回届くと 2 回出す。購買の受け手は回答が空のときだけ書くので、結果は変わらない
    def self.publish_rejected(order, event)
      Contracts.publish(Contracts::CancellationRejected.new(cancellation_request_id: event.cancellation_request_id,
        purchase_order_id: event.purchase_order_id, buyer_tenant_id: order.customer_tenant_id, supplier_tenant_id: order.owner_tenant_id))
    end
    private_class_method :review, :publish_rejected
  end
end
