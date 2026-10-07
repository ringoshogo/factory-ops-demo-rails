class CreateCurrentTenantId < ActiveRecord::Migration[8.1]
  # RLS のポリシーが比べる、トランザクションのテナント（docs/architecture/data-model.md「RLS」）。
  # app.tenant_id が未設定なら NULL を返し、どの行にも一致しない
  def up
    safety_assured do
      execute <<~SQL
        CREATE FUNCTION current_tenant_id() RETURNS uuid LANGUAGE sql STABLE AS
        $$ SELECT nullif(current_setting('app.tenant_id', true), '')::uuid $$;
      SQL
    end
  end

  def down
    safety_assured { execute "DROP FUNCTION current_tenant_id()" }
  end
end
