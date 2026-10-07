class CreateTenants < ActiveRecord::Migration[8.1]
  def change
    create_table :tenants, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :partner_code, null: false
      t.timestamps

      t.index :code, unique: true
      t.index :partner_code, unique: true
    end
  end
end
