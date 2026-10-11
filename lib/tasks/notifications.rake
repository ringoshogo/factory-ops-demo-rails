# 再試行を使い切ったか、再試行しない応答で失敗した確実な送信を、同じ送信記録のまま登録し直す（docs/adr/007 決定 2）。
# 原因（API キー・宛先の設定・提供元の障害）が解消した後に、運用者が流す。テナントを明示して 1 つずつ回る（decisions.md 2 章）
namespace :notifications do
  desc "SINCE（ISO 8601 の時刻）以降に失敗した確実な送信を登録し直す"
  task redeliver: :environment do
    since = Time.iso8601(ENV.fetch("SINCE") { abort "notifications:redeliver: SINCE=2026-10-12T00:00:00+09:00 の形で時刻を渡す" })
    tenant_ids = ActiveRecord::Base.lease_connection.select_values("SELECT id FROM tenants ORDER BY id")
    total = tenant_ids.sum do |tenant_id|
      Tenancy.with_tenant(tenant_id) { Notifications::Email.redeliver_failed(since:) }.tap do |count|
        puts "notifications:redeliver: テナント #{tenant_id} の #{count} 件を登録し直した" if count.positive?
      end
    end
    puts "notifications:redeliver: 合わせて #{total} 件"
  end
end
