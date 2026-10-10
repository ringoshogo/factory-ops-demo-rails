# DB のタスクを、ロールの分け方（docs/architecture/data-model.md「RLS」）に合わせる。
# config/database.yml は、アプリのロールの primary と、所有ロールの owner を同じ DB に置いている。
namespace :db do
  # Rails の pg_dump は権限を落とす（--no-privileges）ので、権限を structure.sql に載せてもテスト DB に再現されない。
  # そのため、表を作るタスクの後にこのタスクを走らせる。
  desc "アプリの DB ロールに、表と連番の権限を付与する"
  task grant_app_role: :load_config do
    environments = [ ActiveRecord::Tasks::DatabaseTasks.env ]
    # Rails の DB タスクと同じく、開発環境で流したときはテスト DB も対象にする
    environments << "test" if environments.first == "development" && !ENV["SKIP_TEST_DATABASE"]

    environments.each do |env|
      app = ActiveRecord::Base.configurations.configs_for(env_name: env, name: "primary", include_hidden: true)
      owner = owner_config!(env)

      ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(owner) do |connection|
        # 開発環境で db:migrate を流したとき、テスト DB はまだ空のことがある。db:test:prepare の後に付与する
        next unless connection.data_source_exists?("schema_migrations")

        role = connection.quote_column_name(app.configuration_hash.fetch(:username))
        connection.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{role}")
        connection.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{role}")
        # マイグレーションの記録はアプリから書き換えさせない
        connection.execute("REVOKE INSERT, UPDATE, DELETE ON schema_migrations, ar_internal_metadata FROM #{role}")
        # tenants は RLS を付けない表なので、書き換えを許すと他社の名前や取引用コードを変えられる
        connection.execute("REVOKE UPDATE, DELETE ON tenants FROM #{role}")
        # 監査ログは追記だけにする。所有ロールの書き換えと削除は、表のトリガーが止める
        connection.execute("REVOKE UPDATE, DELETE ON audit_logs FROM #{role}") if connection.data_source_exists?("audit_logs")
      end
    rescue ActiveRecord::NoDatabaseError
      next
    end
  end

  # db:rollback などは、設定ごとに回さず ActiveRecord::Base の接続でマイグレーションを流す。
  # そのままではアプリのロールで流れて権限で落ちるので、所有ロールに切り替える
  task connect_as_owner: :load_config do
    ActiveRecord::Base.establish_connection(owner_config!(ActiveRecord::Tasks::DatabaseTasks.env))
  end

  # 本番の owner は、所有ロールの資格情報を渡したマイグレーションの工程にだけある（config/database.yml）
  def owner_config!(env)
    ActiveRecord::Base.configurations.configs_for(env_name: env, name: "owner") or
      abort "#{env} に owner の DB 設定が無い。本番では DB_OWNER_USER と DB_OWNER_PASSWORD を渡して DB のタスクを流す"
  end
end

%w[db:rollback db:forward db:migrate:up db:migrate:down db:migrate:redo].each do |name|
  Rake::Task[name].enhance([ "db:connect_as_owner" ])
end

%w[db:migrate db:migrate:up db:forward db:schema:load db:test:load_schema db:prepare].each do |name|
  Rake::Task[name].enhance do
    # 1 回のコマンドで複数のタスクから呼ばれるので、invoke ではなく execute で毎回走らせる
    Rake::Task["db:grant_app_role"].execute
  end
end
