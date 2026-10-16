module Sales
  # 出荷が受注を読み、受注に出荷済を書く入口（docs/architecture/context-map.md「コンテキスト間の関係」、
  # docs/adr/012-同じテナントの中の連結を同期にし出荷可能だけをイベントで残す.md）。
  # 3 つとも Scope の自社の受注だけを読み書きし、他社の受注には当たらない
  module OrderShipping
    # lock が返す、ロックした受注の取消済と審査中。出荷済は返さない。出荷が自分の出荷実績で読み、受注の出荷済は計上が同じトランザクションで書くからである
    State = Data.define(:cancelled, :under_review)

    # 自社の受注ごとに、取消済か（cancelled）と、決着していない取消の審査があるか（under_review）を返す副問い合わせ。
    # 出荷依頼の状況の SQL の式が結ぶ（docs/adr/010-状況の導出をSQLの式1つにする.md）。操作者の scope を掛けた後に SQL の文字列にするので、
    # 受け取る側は条件を外せない。審査は所有テナントと受注の組の外部キーで受注と同じテナントに限られる
    def self.status_sql(actor)
      orders = SalesOrder.arel_table
      reviews = CancellationReview.pending.where(CancellationReview.arel_table[:sales_order_id].eq(orders[:id]))
      SqlSubquery.of(Scope.sales_orders(actor, :own).select(:id, orders[:cancelled_at].not_eq(nil).as("cancelled"),
        reviews.arel.exists.as("under_review")), sales_order_id: "id", cancelled: "cancelled", under_review: "under_review")
    end

    # 自社の受注の行を FOR UPDATE でロックし、取消済と審査中を返す。見えない受注は nil で、何もロックしない。
    # 受注の取消・審査の作成と決着もこの行を最初にロックするので、出荷指示の作成と計上はそれらと受注の行ロックで直列になる
    # （docs/architecture/data-model.md「取消と出荷の競合を止める場所」）
    def self.lock(actor, sales_order_id)
      order = Scope.sales_orders(actor, :own).lock.find_by(id: sales_order_id)
      return unless order

      State.new(cancelled: !order.cancelled_at.nil?, under_review: order.cancellation_reviews.pending.exists?)
    end

    # 自社の受注に、出荷済の時刻が空のときだけ書く。見えない受注には書かずに NOT_FOUND を返す。呼ぶ側が lock を取った後に呼ぶ
    def self.mark_shipped(actor, sales_order_id)
      order = Scope.sales_orders(actor, :own).find_by(id: sales_order_id)
      return OperationResult.failure(:not_found, path: [ :sales_order_id ]) unless order

      order.update!(shipped_at: Time.current) unless order.shipped_at
      OperationResult.success
    end
  end
end
