module Sales
  # 取消の審査の承認と却下（docs/architecture/context-map.md「取消の流れ」3、docs/architecture/graphql-schema.md「mutation の一覧」）。
  # 同じ受注の審査の決着と取消依頼の受け手は、受注の行ロックで直列にする
  module CancellationReviews
    # 見えない ID は存在しない ID と同じく nil になる
    def self.find(actor, id)
      Scope.cancellation_reviews(actor, :own).where(id:).map { to_value(_1) }.first
    end

    # 受注 ID ごとの審査。古い順に並べ、見えない受注の ID は空の配列になる
    def self.for_sales_orders(actor, order_ids)
      reviews = CancellationReview.where(sales_order_id: Scope.sales_orders(actor, :own).where(id: order_ids).select(:id)).order(:id)
      order_ids.index_with { [] }.merge(reviews.map { to_value(_1) }.group_by(&:sales_order_id))
    end

    # 受注を取り消して（引当の解除と cancelled_at）、審査を承認で決着させ、「取消承認」を出す。
    # 引当が消費済み（出荷の計上が先に成立した）なら CONFLICT で、担当者は却下する
    def self.approve(actor, cancellation_review_id:)
      decide(actor, cancellation_review_id, "approved") { |order| OrderCancelling.cancel(actor, order) }
    end

    # 審査を却下で決着させ、「取消却下」を出す。受注と引当は変えない。審査が決着すると、出荷はその受注の出荷依頼を出荷停止中と導出しなくなる
    def self.reject(actor, cancellation_review_id:)
      decide(actor, cancellation_review_id, "rejected") { OperationResult.success }
    end

    def self.to_value(review)
      CancellationReviewValue.new(id: review.id, owner_tenant_id: review.owner_tenant_id, sales_order_id: review.sales_order_id,
        requested_at: review.requested_at, decision: review.decision&.to_sym, decided_at: review.decided_at)
    end

    # 決着済みの審査は CONFLICT。決着の処理（ブロック）が失敗を返したら、セーブポイントまで戻して失敗を返す
    def self.decide(actor, review_id, decision)
      review = Scope.cancellation_reviews(actor, :own).find_by(id: review_id)
      return OperationResult.failure(:not_found, path: [ :cancellation_review_id ]) unless review

      result = nil
      SalesOrder.transaction(requires_new: true) do
        order = SalesOrder.lock.find(review.sales_order_id)
        # 受注のロックを取ってから読み直し、先に決着した審査を見落とさない
        review.reload
        result = review.decision ? OperationResult.failure(:conflict, message: "Cancellation review is already decided") : yield(order)
        raise ActiveRecord::Rollback unless result.success?

        review.update!(decision:, decided_at: Time.current, decided_by_user_id: actor.user_id)
        publish_answer(decision, order, review)
      end
      result.success? ? OperationResult.success(SalesOrders.find(actor, review.sales_order_id)) : result
    end

    # 発生の時刻は審査の決着の時刻にする。承認で書く受注の cancelled_at は、同じトランザクションの少し前の時刻である
    def self.publish_answer(decision, order, review)
      event = decision == "approved" ? Contracts::CancellationApproved : Contracts::CancellationRejected
      Contracts.publish(event.new(cancellation_request_id: review.source_cancellation_request_id,
        purchase_order_id: order.source_purchase_order_id, buyer_tenant_id: order.customer_tenant_id,
        supplier_tenant_id: order.owner_tenant_id, occurred_at: review.decided_at.iso8601(6)))
    end
    private_class_method :to_value, :decide, :publish_answer
  end
end
