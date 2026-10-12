module Sales
  # 受注側が自社の品目カタログを読み書きする（docs/architecture/graphql-schema.md「読み取りの一覧」「mutation の一覧」）。
  # 品目の値の単価は、今日の単価を item_prices から引く（docs/adr/006 決定 5）
  module Catalog
    # 並べてよい列（docs/architecture/graphql-schema.md「ページングと N+1」）
    ORDER_COLUMNS = { code: [ Item.arel_table[:code], :string ], name: [ Item.arel_table[:name], :string ] }.freeze

    # order_by は { field:, direction: } で、省けば作った順の新しいものから並べる。filter の keyword で品目コードか品目名を検索する
    def self.items(actor, first:, after:, order_by: nil, filter: {})
      Page.of(searched(Scope.call(actor, :own), **filter), first:, after:, sort: Page::Sort.of(order_by, ORDER_COLUMNS)) do |items|
        to_values(actor, items)
      end
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.item(actor, id)
      to_values(actor, Scope.call(actor, :own).where(id:)).first
    end

    # 品目 ID ごとの自社の品目。見えない ID は含まない
    def self.items_for(actor, ids)
      to_values(actor, Scope.call(actor, :own).where(id: ids)).index_by(&:id)
    end

    # 品目コードで自社の品目を引き、無ければ作り、あれば更新する。公開の状態は変えない（変えるのは set_published と bulk_upsert）。
    # 新しい品目には、単価を有効期間 (,) の行として足す。既存の品目の単価は変えず、今日の単価と違う値は INVALID_INPUT にする。
    # 単価の改定と訂正は、admin に限る ItemPrices の操作だけが行う（docs/architecture/context-map.md「自社の中の役割」）。
    # 同じ値は、品目の名前や単位を直すときにも単価が必須の引数として届くので、無視する。
    # 同じコードの同時の作成は一意索引が拒否する。セーブポイントまで戻してから失敗を返す
    def self.save(actor, code:, name:, unit:, unit_price:, tax_rate_percent:)
      item = Item.transaction(requires_new: true) do
        record = Scope.call(actor, :own).lock.find_or_initialize_by(code:)
        next if record.persisted? && ItemPrices.price_at(actor, [ record.id ], valid_on: ItemPrice.today)[record.id] != unit_price

        created = record.new_record?
        record.update!(name:, unit:, tax_rate_percent:)
        if created
          ItemPrice.add!(item_id: record.id, unit_price:, valid_from: nil, valid_to: nil, at: Time.current, recorded_by_user_id: actor.user_id)
        end
        record
      end
      return OperationResult.success(to_values(actor, [ item ]).first) if item

      OperationResult.failure(:invalid_input, path: [ :unit_price ],
        message: "既存の品目の単価は変えられない。単価の改定は scheduleItemPrice を、入力の誤りの訂正は correctItemPrice を使う")
    rescue ActiveRecord::RecordInvalid => e
      error = e.record.errors.first
      OperationResult.failure(:invalid_input, path: [ error.attribute ], message: error.full_message)
    rescue ActiveRecord::RecordNotUnique
      OperationResult.failure(:conflict, path: [ :code ])
    end

    # bulk_upsert の 1 行の結果。created は、この呼び出しで品目を作ったか
    Upserted = Data.define(:item_id, :created)

    # 取り込みの品目の行を、品目コードで書く（docs/architecture/data-model.md「取り込み（`imports`）」）。rows は
    # { code:, name:, unit:, tax_rate_percent:, published:, unit_price: } の配列で、コードは重ならず、列は呼ぶ側が検証した値である。
    # 品目の列は 1 つの upsert_all で書き、新しい品目には unit_price を有効期間 (,) の単価の行として足す（save と同じ形）。
    # 既存の品目の単価には触れない。単価の改定は、admin に限る ItemPrices の操作だけが行う。
    # 単価の空の新しい品目は書かずに INVALID_INPUT にする。品目コードごとの結果を返す。
    # upsert は既存の品目の行をロックするので、同じ品目への save・改定の予約とは品目の行ロックで直列になる。
    # 行をコードの順に並べ、並んだ取り込みがロックを同じ順で取るようにする。同じ新しいコードを並んで書くと、後の upsert は
    # 一意索引で先のコミットを待ってから更新に回り、作った品目として数えないので、最初の単価の行は 1 つになる
    def self.bulk_upsert(actor, rows)
      rows = rows.sort_by { _1[:code] }
      existing = Scope.call(actor, :own).where(code: rows.map { _1[:code] }).pluck(:code).to_set
      rejected, writable = rows.partition { |row| row[:unit_price].nil? && !existing.include?(row[:code]) }
      results = rejected.to_h do |row|
        [ row[:code], OperationResult.failure(:invalid_input, path: [ :unit_price ], message: "Unit price is required for a new item") ]
      end
      return results if writable.empty?

      written = Item.upsert_all(
        writable.map { { owner_tenant_id: Current.tenant_id, **_1.slice(:code, :name, :unit, :tax_rate_percent, :published) } },
        unique_by: %i[owner_tenant_id code], returning: Arel.sql("id, code, xmax = 0 AS created")
      )
      at = Time.current
      prices = writable.to_h { [ _1[:code], _1[:unit_price] ] }
      written.each do |item|
        if item["created"]
          ItemPrice.add!(item_id: item["id"], unit_price: prices.fetch(item["code"]), valid_from: nil, valid_to: nil, at:,
            recorded_by_user_id: actor.user_id)
        end
        results[item["code"]] = OperationResult.success(Upserted.new(item_id: item["id"], created: item["created"]))
      end
      results
    end

    # 品目コードごとの自社の品目 ID。見えないコードと無いコードは含まない
    def self.ids_by_codes(actor, codes)
      Scope.call(actor, :own).where(code: codes).pluck(:code, :id).to_h
    end

    def self.set_published(actor, item_id:, published:)
      item = Scope.call(actor, :own).lock.find_by(id: item_id)
      return OperationResult.failure(:not_found, path: [ :item_id ]) unless item

      item.update!(published:)
      OperationResult.success(to_values(actor, [ item ]).first)
    end

    # keyword の前後の空白（全角の空白を含む）を除き、品目コードか品目名に含む品目に、大文字と小文字を区別せずに絞る。
    # % と _ はワイルドカードにせず、文字として探す。空の keyword は絞らない
    def self.searched(relation, keyword: nil)
      keyword = keyword.to_s.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
      return relation if keyword.empty?

      # sanitize_sql_like は % と _ と \ の前に \ を置く。ESCAPE を明示して DB の既定のエスケープ文字に頼らず、
      # case_sensitive: false で PostgreSQL の ILIKE にする（Arel::Predications#matches、activerecord 8.1）
      pattern = "%#{Item.sanitize_sql_like(keyword)}%"
      code, name = %i[code name].map { Item.arel_table[_1] }
      relation.where(code.matches(pattern, "\\", false).or(name.matches(pattern, "\\", false)))
    end

    # 今日の単価は品目の一覧に対して 1 回で引く
    def self.to_values(actor, items)
      items = items.to_a
      prices = ItemPrices.price_at(actor, items.map(&:id), valid_on: ItemPrice.today)
      items.map do |item|
        ItemValue.new(**item.slice(*(ItemValue.members - [ :unit_price ]).map(&:to_s)).symbolize_keys, unit_price: prices.fetch(item.id))
      end
    end
    private_class_method :searched, :to_values
  end
end
