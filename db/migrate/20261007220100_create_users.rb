class CreateUsers < ActiveRecord::Migration[8.1]
  include TenantTable

  def change
    create_tenant_table :users do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :role, null: false
      t.timestamps

      t.index :email, unique: true
      # role IN (...) と書くと、structure.sql を読み込み直したときに式の表記が変わり、差分検査が落ちる
      t.check_constraint "role::text IN ('admin', 'member')", name: "users_role_check"
    end
  end
end
