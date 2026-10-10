class CreatePartnerships < ActiveRecord::Migration[8.1]
  include TenantTable

  # 取引関係と権限付与、読む経路 2 のポリシー（docs/architecture/data-model.md「取引関係と権限付与（`partnerships`）」「RLS」）
  def change
    # owner_tenant_id は受注側。失効させた関係は再び有効にせず、取引を再開するときは新しい関係を結ぶので、
    # 一意にするのは有効な関係だけにする
    create_tenant_table :partnerships do |t|
      t.uuid :buyer_tenant_id, null: false
      t.string :status, null: false, default: "active"
      t.datetime :revoked_at
      t.timestamps

      t.index [ :owner_tenant_id, :buyer_tenant_id ], unique: true, where: "(status)::text = 'active'::text",
        name: "index_partnerships_active_pair"
      t.index :buyer_tenant_id
      t.check_constraint "owner_tenant_id <> buyer_tenant_id", name: "partnerships_not_self"
      t.check_constraint "(((status)::text = 'active'::text) AND (revoked_at IS NULL)) OR " \
        "(((status)::text = 'revoked'::text) AND (revoked_at IS NOT NULL))", name: "partnerships_status_revoked_at"
    end

    create_tenant_table :partnership_grants do |t|
      t.string :permission, null: false
      t.timestamps

      t.check_constraint "(permission)::text = ANY (ARRAY['view_catalog'::text, 'place_orders'::text, 'view_shipments'::text])",
        name: "partnership_grants_permission_check"
    end
    add_tenant_reference :partnership_grants, :partnerships
    add_index :partnership_grants, [ :partnership_id, :permission ], unique: true

    reversible do |dir|
      dir.up do
        # 呼び出し元の権限で partnerships を読む。RLS を通るので、失効した関係は判定でも見えない。SECURITY DEFINER にしない
        safety_assured do
          execute <<~SQL
            CREATE FUNCTION partnership_active(supplier uuid, buyer uuid) RETURNS boolean LANGUAGE sql STABLE AS
            $$ SELECT EXISTS (SELECT 1 FROM partnerships p
                              WHERE p.owner_tenant_id = supplier AND p.buyer_tenant_id = buyer AND p.status = 'active') $$;
          SQL
        end
      end
      dir.down do
        safety_assured { execute "DROP FUNCTION partnership_active(uuid, uuid)" }
      end
    end

    # 経路 2：自社が発注側である有効な取引関係と、その権限付与
    add_partner_read_policy :partnerships, using: "buyer_tenant_id = current_tenant_id() AND status = 'active'"
    add_partner_read_policy :partnership_grants, using: "EXISTS (SELECT 1 FROM partnerships p WHERE p.id = partnership_id)"
  end
end
