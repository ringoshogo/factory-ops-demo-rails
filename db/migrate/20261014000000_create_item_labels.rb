class CreateItemLabels < ActiveRecord::Migration[8.1]
  include TenantTable

  # 在庫の一覧を品目のコードと名前で並べ、検索するための品目の写し（docs/architecture/data-model.md「在庫（`inventory`）」、docs/adr/011）。
  # 既存の DB の写しは埋めない。マイグレーションの後に bin/rails read_models:rebuild を流す（docs/adr/001 決定 4）
  def change
    create_tenant_table :item_labels, comment: "[在庫] 品目のコードと名前の写し。在庫の一覧を並べ、検索するために、受注の品目から写す" do |t|
      # 受注の品目の ID。写しの抜けは一致の spec で捕まえ、外部キーは張らない
      t.uuid :item_id, null: false
      t.string :code, null: false
      t.string :name, null: false
      t.timestamps

      # 写しを書く upsert の衝突の対象。所有テナントを含めるので、他社の写しには当たらない
      t.index [ :owner_tenant_id, :item_id ], unique: true
    end
  end
end
