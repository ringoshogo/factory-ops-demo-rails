-- DB ロールを 2 つに分ける（docs/architecture/data-model.md「RLS」）。
-- compose.yaml がボリュームの初回作成時に流し、CI は psql で流す。何度流してもよい。
DO $$
BEGIN
  -- 表の所有者。マイグレーションとスキーマの読み込みを行う。
  -- BYPASSRLS は、M4 の認証専用の関数（SECURITY DEFINER）が FORCE の表を引くのに要る
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'factory_owner') THEN
    CREATE ROLE factory_owner LOGIN CREATEDB BYPASSRLS PASSWORD 'factory_owner';
  END IF;

  -- アプリ・テスト・ワーカーが接続するロール。所有者でも BYPASSRLS でもないので、RLS が必ず掛かる
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'factory_app') THEN
    CREATE ROLE factory_app LOGIN NOSUPERUSER NOBYPASSRLS PASSWORD 'factory_app';
  END IF;
END
$$;
