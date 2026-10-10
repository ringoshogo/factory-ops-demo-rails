# 保存期間を過ぎた監査ログを消す（docs/architecture/data-model.md「監査ログ（`platform`）」）。
# アプリのロールには audit_logs の DELETE の権限が無いので、所有ロールの資格情報を持つ運用の工程で月に 1 回流す
namespace :audit do
  desc "保存期間を過ぎた監査ログを消す（所有ロールで流す）"
  task purge: "db:load_config" do
    owner = owner_config!(ActiveRecord::Tasks::DatabaseTasks.env)
    ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(owner) do |connection|
      puts "audit:purge: #{connection.select_value('SELECT purge_expired_audit_logs()')} 行を消した"
    end
  end
end
