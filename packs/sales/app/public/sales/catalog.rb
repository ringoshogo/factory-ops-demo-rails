module Sales
  # 受注側が自社の品目カタログを読み書きする（docs/architecture/graphql-schema.md「読み取りの一覧」「mutation の一覧」）
  module Catalog
    def self.items(actor, first:, after:)
      Page.of(Scope.call(actor, :own), first:, after:) { |items| items.map { to_value(_1) } }
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.item(actor, id)
      item = Scope.call(actor, :own).find_by(id:)
      item && to_value(item)
    end

    # 品目 ID ごとの自社の品目。見えない ID は含まない
    def self.items_for(actor, ids)
      Scope.call(actor, :own).where(id: ids).to_h { [ _1.id, to_value(_1) ] }
    end

    # 品目コードで自社の品目を引き、無ければ作り、あれば更新する。公開の状態は set_published だけが変える。
    # 同じコードの同時の作成は一意索引が拒否する。セーブポイントまで戻してから失敗を返す
    def self.save(actor, code:, name:, unit:, unit_price:, tax_rate_percent:)
      item = Item.transaction(requires_new: true) do
        Scope.call(actor, :own).lock.find_or_initialize_by(code:).tap do |record|
          record.update!(name:, unit:, unit_price:, tax_rate_percent:)
        end
      end
      OperationResult.success(to_value(item))
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
      OperationResult.success(to_value(item))
    end

    def self.to_value(item)
      ItemValue.new(**item.slice(*ItemValue.members.map(&:to_s)).symbolize_keys)
    end
    private_class_method :to_value
  end
end
