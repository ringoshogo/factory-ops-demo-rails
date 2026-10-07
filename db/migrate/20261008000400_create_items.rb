class CreateItems < ActiveRecord::Migration[8.1]
  include TenantTable

  # 品目カタログと、読む経路 1 のポリシー（docs/architecture/data-model.md「受注」「RLS」）
  def change
    create_tenant_table :items do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :unit, null: false
      t.bigint :unit_price, null: false
      t.integer :tax_rate_percent, null: false, default: 10
      t.boolean :published, null: false, default: false
      t.timestamps

      t.index [ :owner_tenant_id, :code ], unique: true
      t.check_constraint "unit_price >= 0", name: "items_unit_price_non_negative"
      t.check_constraint "tax_rate_percent = ANY (ARRAY[8, 10])", name: "items_tax_rate_percent_check"
    end

    # 経路 1：有効な取引関係の発注側に、公開品目だけを見せる。view_catalog の付与はアプリの policy scope が判定する
    add_partner_read_policy :items, using: "published AND partnership_active(owner_tenant_id, current_tenant_id())"
  end
end
