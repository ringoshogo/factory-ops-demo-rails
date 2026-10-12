module Fulfillment
  # 受注からのイベントの受け手。受注側テナントの名義で、自社の出荷依頼・出荷指示・出荷停止だけを書く
  # （docs/architecture/data-model.md「イベントの受け口と冪等キー」）。取引関係の状態は見ない。
  # 届く順が入れ替わっても停止や出荷依頼を取り残さない（docs/architecture/data-model.md「イベントの届く順の入れ替わり」）。
  # イベントの受け手は操作者のいない入口なので、テナントの設定を求め、所有の条件を RLS に任せずに書き、値を返さない
  # （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
  module SalesEventReceiver
    def self.handle(event)
      Tenancy.require_tenant!
      case event
      when Contracts::SalesOrderReadyForShipment then create_request(event)
      when Contracts::ShippingHeld then hold(event)
      when Contracts::ShippingHoldReleased then release(event)
      when Contracts::ShipmentCancelled then cancel(event)
      else raise ArgumentError, "unexpected event: #{event.class}"
      end
      nil
    end

    # 「出荷可能」の写しを作る。冪等キーは sales_order_id で、2 回目の配送では何もしない。同時に届いた配送は一意索引が止める。
    # 出荷依頼の有無を読む前に受注のロックを取り、出荷停止の受け手と直列にする
    def self.create_request(event)
      lock_sales_order(event.sales_order_id)
      return if own_requests.exists?(sales_order_id: event.sales_order_id)

      ShipmentRequest.transaction(requires_new: true) do
        ShipmentRequest.create!(
          owner_tenant_id: Current.tenant_id,
          sales_order_id: event.sales_order_id,
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

    # 解除前の出荷停止を書く。冪等キーは審査 ID で、行があれば（解除が先に届いて解除済みの行があっても）何もしない。
    # 出荷依頼があれば行をロックしてから書き、同じ出荷依頼の計上と出荷指示の作成と直列にする。
    # 出荷依頼がまだ無いときに備えて、先に受注のロックを取る
    def self.hold(event)
      lock_sales_order(event.sales_order_id)
      own_requests.lock.find_by(sales_order_id: event.sales_order_id)
      ShippingHold.insert(hold_row(event.cancellation_review_id, event.sales_order_id, released_at: nil),
        unique_by: :source_cancellation_review_id)
    end

    # 出荷停止を解除する。停止より先に届いたら、解除済みの行を先に作り、後から届く停止を何もさせない
    def self.release(event)
      release_hold(event.cancellation_review_id, event.sales_order_id)
    end

    # 出荷依頼を取消済にし、有効な出荷指示を取り消し、受注の出荷停止をすべて解除する。
    # 「出荷可能」を出した受注なのに出荷依頼がまだ無ければ、出荷可能より先に届いたので失敗させ、再配送に任せる。
    # 出荷依頼は出荷可能の値からしか作れないので、解除済みの停止のような先回りの行を作らない
    def self.cancel(event)
      request = own_requests.lock.find_by(sales_order_id: event.sales_order_id)
      if request.nil? && event.ready_for_shipment
        raise ActiveRecord::RecordNotFound, "出荷取消が出荷可能より先に届いた: #{event.sales_order_id}"
      end

      if request && !request.cancelled_at
        request.instructions.active.lock.each { _1.update!(status: "cancelled") }
        request.update!(cancelled_at: Time.current)
      end
      ShippingHold.active.where(owner_tenant_id: Current.tenant_id, sales_order_id: event.sales_order_id).update_all(released_at: Time.current, updated_at: Time.current)
      release_hold(event.cancellation_review_id, event.sales_order_id) if event.cancellation_review_id
    end

    # 審査の出荷停止を解除済みにする。行が無ければ解除済みの行を作る。1 文の upsert にするのは、行を読んでから書く間に
    # 停止が割り込んで解除前の行を作り、解除が失われることを防ぐためである。解除の時刻は最初に解除したときのまま変えない。
    # 審査 ID の一意索引はテナントをまたぐので、他社の同じ審査 ID の行に当たったときに備え、更新に所有の条件を書く。
    # 当たれば行を作りも書きもしないので、失敗させて知らせる
    def self.release_hold(cancellation_review_id, sales_order_id)
      now = Time.current
      written = ShippingHold.upsert(hold_row(cancellation_review_id, sales_order_id, released_at: now),
        unique_by: :source_cancellation_review_id, returning: :id,
        on_duplicate: Arel.sql("released_at = COALESCE(shipping_holds.released_at, EXCLUDED.released_at), updated_at = EXCLUDED.updated_at " \
          "WHERE shipping_holds.owner_tenant_id = EXCLUDED.owner_tenant_id"))
      raise ActiveRecord::RecordNotFound, "他社の出荷停止と同じ審査 ID: #{cancellation_review_id}" if written.rows.empty?
    end

    # 受注ごとのアドバイザリロックを、トランザクションの終わりまで取る。出荷依頼がまだ無い受注には行ロックを掛ける行が無いので、
    # 停止の受け手が出荷依頼の無いことを読んでからコミットするまでの間に、出荷可能の受け手が出荷依頼を作り、出荷指示の作成が
    # 停止を読まずに通ってしまう。停止の受け手と出荷可能の受け手の両方がこのロックを取り、どちらか一方を先に終わらせる。
    # テナントの設定は Tenancy.with_tenant のトランザクションの中にだけあるので、ロックはそのトランザクションの終わりまで残る
    def self.lock_sales_order(sales_order_id)
      Tenancy.require_tenant!
      ShipmentRequest.lease_connection.exec_query("SELECT 1 FROM pg_advisory_xact_lock(hashtextextended($1, 0))", "Fulfillment::SalesEventReceiver",
        [ "shipping:#{Current.tenant_id}:#{sales_order_id}" ])
      nil
    end

    def self.own_requests = ShipmentRequest.where(owner_tenant_id: Current.tenant_id)

    # insert と upsert は TenantRecord の保存の確認を通らないので、ここでテナントの設定を確かめる
    def self.hold_row(cancellation_review_id, sales_order_id, released_at:)
      Tenancy.require_tenant!
      { owner_tenant_id: Current.tenant_id, source_cancellation_review_id: cancellation_review_id, sales_order_id:, released_at: }
    end
    private_class_method :create_request, :hold, :release, :cancel, :release_hold, :lock_sales_order, :own_requests, :hold_row
  end
end
