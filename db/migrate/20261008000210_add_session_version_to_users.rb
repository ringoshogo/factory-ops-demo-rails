class AddSessionVersionToUsers < ActiveRecord::Migration[8.1]
  # セッションの世代（docs/architecture/data-model.md「取引関係と権限付与（`partnerships`）」の users）。
  # Cookie のセッションはサーバーに残らないので、ログアウトとパスワードの変更で世代を進め、前の世代の Cookie を拒む
  def up
    add_column :users, :session_version, :integer, null: false, default: 0

    safety_assured do
      # パスワードを変える経路を問わず世代を進めるため、アプリではなくトリガーで進める
      execute <<~SQL
        CREATE FUNCTION bump_session_version() RETURNS trigger
        LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS
        $$ BEGIN
          NEW.session_version := OLD.session_version + 1;
          RETURN NEW;
        END $$;

        CREATE TRIGGER users_bump_session_version BEFORE UPDATE OF password_digest ON users
        FOR EACH ROW WHEN (OLD.password_digest IS DISTINCT FROM NEW.password_digest)
        EXECUTE FUNCTION bump_session_version();
      SQL

      # 戻り値の列を変えるので、作り直す
      execute "DROP FUNCTION find_login_user(text)"
      execute <<~SQL
        CREATE FUNCTION find_login_user(login_email text)
        RETURNS TABLE (id uuid, owner_tenant_id uuid, password_digest character varying, session_version integer)
        LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS
        $$ SELECT u.id, u.owner_tenant_id, u.password_digest, u.session_version FROM public.users u WHERE u.email = login_email $$;
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP FUNCTION find_login_user(text)"
      execute <<~SQL
        CREATE FUNCTION find_login_user(login_email text)
        RETURNS TABLE (id uuid, owner_tenant_id uuid, password_digest character varying)
        LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS
        $$ SELECT u.id, u.owner_tenant_id, u.password_digest FROM public.users u WHERE u.email = login_email $$;
      SQL
      execute "DROP TRIGGER users_bump_session_version ON users"
      execute "DROP FUNCTION bump_session_version()"
    end
    remove_column :users, :session_version
  end
end
