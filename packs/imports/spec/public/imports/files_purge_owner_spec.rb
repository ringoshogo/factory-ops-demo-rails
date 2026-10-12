require "rails_helper"
require_relative "../../../../../spec/support/owner_connection"

# 置いたままのファイルの後始末は、候補を選ぶ文に所有の条件を書き、RLS が無くても他社のファイルを選ばない
# （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）。RLS も同じ行を閉じるので、
# アプリのロールで流すと条件を落としても気付けない。後始末が流した候補の文を、BYPASSRLS を持つ所有ロールの接続で流し直して
# 確かめる。所有ロールの接続は別のセッションなので、例ごとのトランザクションを使わず、作った行は例の後で所有ロールで消す
RSpec.describe Imports::Files, ".purge_abandoned の所有の条件" do
  self.use_transactional_tests = false

  let!(:tenants) { FactoryBot.create_list(:tenant, 2) }
  let!(:files) do
    tenants.map { |tenant| Tenancy.with_tenant(tenant.id) { FactoryBot.create(:import_file, created_at: 25.hours.ago) } }
  end

  after do
    connection = OwnerConnection.lease_connection
    ids = tenants.map { connection.quote(_1.id) }.join(", ")
    connection.execute("DELETE FROM import_files WHERE owner_tenant_id IN (#{ids})")
    connection.execute("DELETE FROM tenants WHERE id IN (#{ids})")
  end

  # 後始末を 1 社目のテナントで流して巻き戻し、候補の行をロックした文とその値を返す
  def candidate_statement
    statements = []
    collect = ->(*, payload) { statements << payload if payload[:sql].match?(/FOR UPDATE/) && payload[:sql].include?("import_files") }
    ActiveSupport::Notifications.subscribed(collect, "sql.active_record") do
      Tenancy.with_tenant(tenants[0].id) do
        Imports::Files.purge_abandoned
        raise ActiveRecord::Rollback
      end
    end
    payload = statements.sole
    binds = payload[:type_casted_binds]
    [ payload[:sql], binds.respond_to?(:call) ? binds.call : binds ]
  end

  def ids_without_rls(sql, binds = []) = OwnerConnection.lease_connection.select_values(sql, "replay", binds) & files.map(&:id)

  it "候補を選ぶ文は、RLS の掛からない接続で流しても、開いたテナントのファイルだけを選ぶ" do
    sql, binds = candidate_statement

    expect(ids_without_rls("SELECT id FROM import_files WHERE content IS NOT NULL")).to match_array(files.map(&:id))
    expect(ids_without_rls(sql, binds)).to eq([ files[0].id ])
  end
end
