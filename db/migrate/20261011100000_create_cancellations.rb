class CreateCancellations < ActiveRecord::Migration[8.1]
  include TenantTable

  # 取消依頼・取消の審査・出荷停止（docs/architecture/data-model.md「購買（`purchasing`）」「受注（`sales`）」「出荷（`fulfillment`）」）。
  # source_cancellation_request_id・source_cancellation_review_id・sales_order_id はコンテキストをまたぐ ID 参照で、外部キーを張らない
  def change
    create_tenant_table :cancellation_requests, comment: "[購買] 取消依頼。回答（承認・却下）が届くまで回答待ちで、発注ごとに 1 件まで" do |t|
      t.string :reason, null: false
      t.string :outcome
      t.datetime :decided_at
      t.timestamps

      t.check_constraint "outcome::text IN ('approved', 'rejected')", name: "cancellation_requests_outcome_check"
      t.check_constraint "(outcome IS NULL) = (decided_at IS NULL)", name: "cancellation_requests_decided_together"
    end
    add_tenant_reference :cancellation_requests, :purchase_orders
    # 回答待ちの取消依頼は発注ごとに 1 件
    add_index :cancellation_requests, :purchase_order_id, unique: true, where: "outcome IS NULL",
      name: "index_cancellation_requests_one_pending_per_order"

    create_tenant_table :cancellation_reviews, comment: "[受注] 取消の審査。取消依頼から作り、承認か却下で決着する" do |t|
      t.uuid :source_cancellation_request_id, null: false
      t.datetime :requested_at, null: false
      t.string :decision
      t.datetime :decided_at
      t.uuid :decided_by_user_id
      t.timestamps

      # 「取消依頼」の冪等キー
      t.index :source_cancellation_request_id, unique: true
      t.check_constraint "decision::text IN ('approved', 'rejected')", name: "cancellation_reviews_decision_check"
      t.check_constraint "(decision IS NULL) = (decided_at IS NULL)", name: "cancellation_reviews_decided_together"
    end
    add_tenant_reference :cancellation_reviews, :sales_orders
    # 審査中の審査は受注ごとに 1 件
    add_index :cancellation_reviews, :sales_order_id, unique: true, where: "decision IS NULL",
      name: "index_cancellation_reviews_one_pending_per_order"

    create_tenant_table :shipping_holds, comment: "[出荷] 出荷停止。取消の審査ごとに 1 件で、解除するまで受注の出荷指示と計上を止める" do |t|
      t.uuid :sales_order_id, null: false
      t.uuid :source_cancellation_review_id, null: false
      t.datetime :released_at
      t.timestamps

      # 「出荷停止」「出荷停止解除」「出荷取消」の冪等キー。解除が停止より先に届くと、解除済みの行を先に作る
      t.index :source_cancellation_review_id, unique: true
      # 解除前の停止を受注ごとに 1 件に限らない。前の審査の解除より、次の審査の停止が先に届くことがあるからである
      t.index :sales_order_id
    end
  end
end
