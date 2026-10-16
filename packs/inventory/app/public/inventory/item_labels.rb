module Inventory
  # 在庫の一覧を品目のコードと名前で並べ、検索し、調整の対象の品目を確かめるための、受注の品目の写し
  # （docs/architecture/data-model.md「在庫（`inventory`）」）。写しを書く put は、受注の公開 API が品目を書くのと同じトランザクションで呼ぶ
  # （docs/adr/011 決定 1）
  module ItemLabels
    # put が足した写しの数と、書き直した写しの数
    Counts = Data.define(:inserted, :updated) do
      def +(other) = Counts.new(inserted: inserted + other.inserted, updated: updated + other.updated)
    end

    # 自社の品目の写し。見えない品目は nil を返す。在庫の調整の mutation が、対象の品目を引く
    def self.find(actor, item_id)
      label = Scope.call(actor, ItemLabel.where(item_id:)).first
      label && ItemLabelValue.new(**label.slice(*ItemLabelValue.members.map(&:to_s)).symbolize_keys)
    end

    # labels は { item_id:, code:, name: } の配列で、品目 ID は重ならない。いまのテナントの写しを upsert し、件数だけを返す。
    # 操作者のいない入口なので、テナントの設定を求め、所有テナントを Current のテナントで明示して書く
    # （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）。
    # 衝突の対象は所有テナントと品目 ID の組の一意索引なので、他社の写しには当たらない。
    # 値の同じ写しは書き直さないので、作り直しのタスクが、書き直した数で写しの食い違いを数えられる。
    # 品目コードの順に書き、品目を同じ順で書く受注の公開 API と、写しの行ロックを同じ順で取る
    def self.put(labels)
      Tenancy.require_tenant!
      return Counts.new(inserted: 0, updated: 0) if labels.empty?

      rows = labels.sort_by { _1[:code] }.map { { owner_tenant_id: Current.tenant_id, **_1.slice(:item_id, :code, :name) } }
      # on_duplicate に SQL を渡すと DO UPDATE SET の後にそのまま置かれ、updated_at を足すのは on_duplicate: :update のときだけなので、
      # updated_at も書く（activerecord 8.1.4 の connection_adapters/postgresql_adapter.rb の build_insert_sql と、
      # insert_all.rb の touch_model_timestamps_unless）。足した行は xmax = 0 で見分ける
      written = ItemLabel.upsert_all(rows, unique_by: %i[owner_tenant_id item_id], returning: Arel.sql("xmax = 0 AS inserted"),
        on_duplicate: Arel.sql(<<~SQL.squish))
          code = EXCLUDED.code, name = EXCLUDED.name, updated_at = EXCLUDED.updated_at
          WHERE (item_labels.code, item_labels.name) IS DISTINCT FROM (EXCLUDED.code, EXCLUDED.name)
        SQL
      inserted = written.count { _1["inserted"] }
      Counts.new(inserted:, updated: written.length - inserted)
    end
  end
end
