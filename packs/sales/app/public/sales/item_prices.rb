module Sales
  # 販売単価の履歴（docs/adr/006）。単価を変える操作は改定の予約（schedule）と訂正（correct）の 2 つだけで、
  # どちらも品目の行をロックしてから、現在の行を閉じて新しい行を足す。単価を引くときは有効日と記録時点を渡す。
  # 記録の時刻は、ロックを取った後に 1 回だけ取る。DB の now() はトランザクションの始まりの時刻なので、ロックを待った操作が、
  # 先にコミットした操作の行をその始まりより前の時刻で閉じようとして失敗する（docs/adr/006 決定 3）
  module ItemPrices
    # 改定日からの単価を予約する。改定日を含む現在の行を閉じ、改定日の前日までの元の単価と、改定日から元の行の終わりまでの
    # 新しい単価の行を足す。改定日を含む行の単価が同じなら何も書かないので、同じ予約をもう一度流しても行は増えない
    def self.schedule(actor, item_id:, unit_price:, effective_on:)
      if effective_on < ItemPrice.today
        return OperationResult.failure(:invalid_input, path: [ :effective_on ], message: "改定日は今日以降にする")
      end

      ItemPrice.transaction(requires_new: true) do
        item = Scope.call(actor, :own).lock.find_by(id: item_id)
        next OperationResult.failure(:not_found, path: [ :item_id ]) unless item

        row = ItemPrice.current.where(item_id: item.id).valid_on(effective_on).first
        next OperationResult.failure(:conflict, path: [ :item_id ], message: "品目に単価の行が無い") unless row

        unless row.unit_price == unit_price
          at = Time.current
          row.close!(at)
          if row.valid_from.nil? || row.valid_from < effective_on
            ItemPrice.add!(item_id: item.id, unit_price: row.unit_price, valid_from: row.valid_from, valid_to: effective_on, at:,
              recorded_by_user_id: actor.user_id)
          end
          ItemPrice.add!(item_id: item.id, unit_price:, valid_from: effective_on, valid_to: row.valid_to, at:,
            recorded_by_user_id: actor.user_id)
        end
        OperationResult.success(Catalog.item(actor, item.id))
      end
    rescue ActiveRecord::RecordInvalid => e
      invalid(e)
    end

    # 現在の行を、同じ有効期間で正しい単価の行に置き換える。閉じた行は訂正できない
    def self.correct(actor, item_price_id:, unit_price:, reason:)
      return OperationResult.failure(:invalid_input, path: [ :reason ], message: "訂正の理由を書く") if reason.blank?

      ItemPrice.transaction(requires_new: true) do
        row = Scope.item_prices(actor, :own).find_by(id: item_price_id)
        next OperationResult.failure(:not_found, path: [ :item_price_id ]) unless row

        # 品目をロックしてから行を読み直す。ロックを待つ間に、ほかの操作がこの行を閉じていることがある
        Scope.call(actor, :own).lock.find(row.item_id)
        row = ItemPrice.current.find_by(id: row.id)
        next OperationResult.failure(:conflict, path: [ :item_price_id ], message: "記録期間が終わった行は訂正できない") unless row

        at = Time.current
        row.close!(at)
        ItemPrice.add!(item_id: row.item_id, unit_price:, valid_from: row.valid_from, valid_to: row.valid_to, at:, reason: reason.strip,
          recorded_by_user_id: actor.user_id)
        OperationResult.success(Catalog.item(actor, row.item_id))
      end
    rescue ActiveRecord::RecordInvalid => e
      invalid(e)
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.find(actor, id)
      Scope.item_prices(actor, :own).find_by(id:)&.then { to_value(_1) }
    end

    # 品目 ID ごとの、有効日の単価。as_of を省けばいま信じている単価を返す。見えない品目と、その時点で単価の無い品目は含まない
    def self.price_at(actor, item_ids, valid_on:, as_of: nil)
      Scope.item_prices(actor, :own).where(item_id: item_ids).valid_on(valid_on).believed_at(as_of).pluck(:item_id, :unit_price).to_h
    end

    # 品目 ID ごとの、as_of の時点で正しいと信じていた行。有効期間の順に並べ、as_of を省けばいま信じている行を返す。
    # 見えない品目の ID は空の配列になる
    def self.history(actor, item_ids, as_of: nil)
      rows = Scope.item_prices(actor, :own).where(item_id: item_ids).believed_at(as_of).in_valid_order
      item_ids.index_with { [] }.merge(rows.map { to_value(_1) }.group_by(&:item_id))
    end

    # 受注明細 ID ごとの単価の説明。as_of は請求書の発行時刻で、空なら発行の時点の単価を空にする。
    # 見えない明細と照合前の明細は含まない
    def self.explain(actor, sales_order_line_ids, as_of:)
      lines = SalesOrderLine.where(id: sales_order_line_ids, sales_order_id: Scope.sales_orders(actor, :own).select(:id))
        .where.not(item_id: nil).to_a
      prices = Scope.item_prices(actor, :own).where(item_id: lines.map(&:item_id).uniq)
      now = prices.current.group_by(&:item_id)
      then_ = as_of ? prices.believed_at(as_of).group_by(&:item_id) : {}
      lines.to_h do |line|
        [ line.id, PriceExplanationValue.new(sales_order_line_id: line.id, ordered_unit_price: line.unit_price, priced_on: line.priced_on,
          unit_price_as_of_issue: ItemPrice.price_on(then_[line.item_id], line.priced_on),
          unit_price_now: ItemPrice.price_on(now[line.item_id], line.priced_on)) ]
      end
    end

    # 単価の履歴を持つ前の DB を、いまのテナントで履歴の形に写す（rake タスク sales:backfill_item_prices が呼ぶ）。
    # 現在の行の無い品目に、items.unit_price を有効期間 (,) の行として足し、照合済みで priced_on の空の明細を受注日で埋める。
    # 行のある品目と埋まった明細は飛ばすので、もう一度流しても行が増えない。items.unit_price を消した後の DB では流さない
    def self.backfill
      Tenancy.require_tenant!
      connection = ItemPrice.connection
      binds = [ Time.current, Current.tenant_id ]
      items = connection.select_value(<<~SQL, "ItemPrices.backfill", binds)
        WITH added AS (
          INSERT INTO item_prices (owner_tenant_id, item_id, unit_price, valid_period, recorded_period)
          SELECT i.owner_tenant_id, i.id, i.unit_price, daterange(NULL, NULL), tstzrange($1, NULL)
          FROM items i
          WHERE i.owner_tenant_id = $2
            AND NOT EXISTS (SELECT 1 FROM item_prices p WHERE p.item_id = i.id AND upper_inf(p.recorded_period))
          RETURNING 1
        )
        SELECT count(*) FROM added
      SQL
      lines = connection.select_value(<<~SQL, "ItemPrices.backfill", binds)
        WITH filled AS (
          UPDATE sales_order_lines l SET priced_on = o.order_date, updated_at = $1
          FROM sales_orders o
          WHERE o.id = l.sales_order_id AND l.owner_tenant_id = $2 AND l.item_id IS NOT NULL AND l.priced_on IS NULL
          RETURNING 1
        )
        SELECT count(*) FROM filled
      SQL
      { items:, lines: }
    end

    # 足す行の検証の失敗。セーブポイントまで戻してから、項目を指す INVALID_INPUT を返す
    def self.invalid(error)
      failure = error.record.errors.first
      OperationResult.failure(:invalid_input, path: [ failure.attribute ], message: failure.full_message)
    end

    def self.to_value(row)
      ItemPriceValue.new(id: row.id, owner_tenant_id: row.owner_tenant_id, item_id: row.item_id, unit_price: row.unit_price,
        valid_from: row.valid_from, valid_to: row.valid_to, recorded_from: row.recorded_from, recorded_to: row.recorded_to,
        reason: row.reason)
    end
    private_class_method :invalid, :to_value
  end
end
