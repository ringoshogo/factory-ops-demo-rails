class CreateFindLoginUser < ActiveRecord::Migration[8.1]
  # ログインの前のユーザー検索（docs/architecture/data-model.md「RLS」）。
  # テナントが決まる前なので users を RLS の下では引けない。RLS の外で動くのはこの関数だけにする。
  # SECURITY DEFINER で所有ロール（BYPASSRLS）の権限で動く。search_path を固定し、呼び出し元の関数や表に差し替えさせない
  def up
    safety_assured do
      execute <<~SQL
        CREATE FUNCTION find_login_user(login_email text)
        RETURNS TABLE (id uuid, owner_tenant_id uuid, password_digest character varying)
        LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS
        $$ SELECT u.id, u.owner_tenant_id, u.password_digest FROM public.users u WHERE u.email = login_email $$;
      SQL
    end
  end

  def down
    safety_assured { execute "DROP FUNCTION find_login_user(text)" }
  end
end
