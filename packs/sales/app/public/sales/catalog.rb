module Sales
  # 受注側が自社の品目カタログを読み書きする（docs/architecture/graphql-schema.md「読み取りの一覧」「mutation の一覧」）。
  # 品目の値の単価は、今日の単価を item_prices から引く（docs/adr/006 決定 5）
  module Catalog
    def self.items(actor, first:, after:)
      Page.of(Scope.call(actor, :own), first:, after:) { |items| to_values(items) }
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.item(actor, id)
      to_values(Scope.call(actor, :own).where(id:)).first
    end

    # 品目 ID ごとの自社の品目。見えない ID は含まない
    def self.items_for(actor, ids)
      to_values(Scope.call(actor, :own).where(id: ids)).index_by(&:id)
    end

    # 品目コードで自社の品目を引き、無ければ作り、あれば更新する。公開の状態は set_published だけが変える。
    # 新しい品目には、単価を有効期間 (,) の行として足す。既存の品目の単価は変えず、今日の単価と違う値は INVALID_INPUT にする。
    # 単価の改定と訂正は、admin に限る ItemPrices の操作だけが行う（docs/architecture/context-map.md「自社の中の役割」）。
    # 同じ値は、品目の名前や単位を直すときにも単価が必須の引数として届くので、無視する。
    # 同じコードの同時の作成は一意索引が拒否する。セーブポイントまで戻してから失敗を返す
    def self.save(actor, code:, name:, unit:, unit_price:, tax_rate_percent:)
      item = Item.transaction(requires_new: true) do
        record = Scope.call(actor, :own).lock.find_or_initialize_by(code:)
        if record.persisted? && ItemPrice.current.where(item_id: record.id).valid_on(ItemPrice.today).pick(:unit_price) != unit_price
          next
        end

        created = record.new_record?
        record.update!(name:, unit:, tax_rate_percent:)
        ItemPrice.add!(item_id: record.id, unit_price:, valid_from: nil, valid_to: nil, at: Time.current) if created
        record
      end
      return OperationResult.success(to_values([ item ]).first) if item

      OperationResult.failure(:invalid_input, path: [ :unit_price ],
        message: "既存の品目の単価は変えられない。単価の改定は scheduleItemPrice を、入力の誤りの訂正は correctItemPrice を使う")
    rescue ActiveRecord::RecordInvalid => e
      error = e.record.errors.first
      OperationResult.failure(:invalid_input, path: [ error.attribute ], message: error.full_message)
    rescue ActiveRecord::RecordNotUnique
      OperationResult.failure(:conflict, path: [ :code ])
    end

    def self.set_published(actor, item_id:, published:)
      item = Scope.call(actor, :own).lock.find_by(id: item_id)
      return OperationResult.failure(:not_found, path: [ :item_id ]) unless item

      item.update!(published:)
      OperationResult.success(to_values([ item ]).first)
    end

    # 単価は品目の一覧に対して 1 回で引く
    def self.to_values(items)
      items = items.to_a
      prices = ItemPrice.current.valid_on(ItemPrice.today).where(item_id: items.map(&:id)).pluck(:item_id, :unit_price).to_h
      items.map do |item|
        ItemValue.new(**item.slice(*(ItemValue.members - [ :unit_price ]).map(&:to_s)).symbolize_keys, unit_price: prices.fetch(item.id))
      end
    end
    private_class_method :to_values
  end
end
