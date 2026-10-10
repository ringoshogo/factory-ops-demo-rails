require "rails_helper"
require_relative "../support/owner_connection"
require_relative "../support/tenant_helpers"

# 監査ログは追記だけで、書き換えも削除もできない（docs/architecture/data-model.md「監査ログ（`platform`）」）。
# アプリのロールは権限で、所有ロールはトリガーで止める。所有ロールの接続は例ごとのトランザクションの外にあるので、
# 所有ロールの example は自分のトランザクションで行を作り、最後に戻す
RSpec.describe "監査ログの追記だけの仕組み" do
  include TenantHelpers

  def insert_audit_log(connection, tenant_id, occurred_at: "now()")
    connection.select_value(<<~SQL)
      INSERT INTO audit_logs (owner_tenant_id, occurred_at, actor_type, action, target_type, target_id, correlation_id)
      VALUES (#{connection.quote(tenant_id)}, #{occurred_at}, 'system', 'event.received', 'PurchaseOrderPlaced', uuidv7(), 'c-1')
      RETURNING id
    SQL
  end

  describe "アプリのロール" do
    let!(:tenant) { create_tenant("audit-app") }
    let!(:id) { Tenancy.with_tenant(tenant) { insert_audit_log(connection, tenant) } }

    it "自社の行を INSERT して読める" do
      expect(Tenancy.with_tenant(tenant) { connection.select_values("SELECT id FROM audit_logs") }).to eq([ id ])
    end

    it "UPDATE は権限で拒まれる" do
      expect {
        Tenancy.with_tenant(tenant) { connection.execute("UPDATE audit_logs SET action = 'x' WHERE id = #{connection.quote(id)}") }
      }.to raise_error(ActiveRecord::StatementInvalid, /permission denied for table audit_logs/)
    end

    it "DELETE は権限で拒まれる" do
      expect {
        Tenancy.with_tenant(tenant) { connection.execute("DELETE FROM audit_logs WHERE id = #{connection.quote(id)}") }
      }.to raise_error(ActiveRecord::StatementInvalid, /permission denied for table audit_logs/)
    end

    it "保存期間を過ぎた行を消す関数も、権限で拒まれる" do
      expect {
        Tenancy.with_tenant(tenant) { connection.select_value("SELECT purge_expired_audit_logs()") }
      }.to raise_error(ActiveRecord::StatementInvalid, /permission denied for table audit_logs/)
    end
  end

  describe "所有ロール" do
    let(:owner) { OwnerConnection.lease_connection }

    # 所有ロールで行を作ってブロックを流し、すべて戻す
    def with_owner_rows
      owner.transaction do
        tenant = owner.select_value(<<~SQL)
          INSERT INTO tenants (code, name, partner_code, created_at, updated_at)
          VALUES ('audit-owner-#{SecureRandom.hex(4)}', 'audit-owner', '#{SecureRandom.hex(16)}', now(), now())
          RETURNING id
        SQL
        yield tenant
        raise ActiveRecord::Rollback
      end
    end

    # 失敗した文は外側のトランザクションを止めるので、セーブポイントの中で流す
    def owner_execute(sql) = owner.transaction(requires_new: true) { owner.execute(sql) }

    it "UPDATE はトリガーで拒まれる" do
      with_owner_rows do |tenant|
        id = insert_audit_log(owner, tenant)

        expect { owner_execute("UPDATE audit_logs SET action = 'x' WHERE id = #{owner.quote(id)}") }
          .to raise_error(ActiveRecord::StatementInvalid, /audit_logs は書き換えられない/)
      end
    end

    it "保存期間の中の行の DELETE はトリガーで拒まれる" do
      with_owner_rows do |tenant|
        id = insert_audit_log(owner, tenant, occurred_at: "now() - interval '7 years' + interval '1 day'")

        expect { owner_execute("DELETE FROM audit_logs WHERE id = #{owner.quote(id)}") }
          .to raise_error(ActiveRecord::StatementInvalid, /保存期間の中の audit_logs の行は消せない/)
      end
    end

    it "TRUNCATE はトリガーで拒まれる" do
      with_owner_rows do |tenant|
        insert_audit_log(owner, tenant)

        expect { owner_execute("TRUNCATE audit_logs") }
          .to raise_error(ActiveRecord::StatementInvalid, /audit_logs は TRUNCATE できない/)
      end
    end

    it "監査の行が指す所有テナントは消せない" do
      with_owner_rows do |tenant|
        insert_audit_log(owner, tenant)

        expect { owner_execute("DELETE FROM tenants WHERE id = #{owner.quote(tenant)}") }
          .to raise_error(ActiveRecord::InvalidForeignKey)
      end
    end

    it "保存期間を過ぎた行を消す関数は、保存期間を過ぎた行だけを消す" do
      with_owner_rows do |tenant|
        expired = insert_audit_log(owner, tenant, occurred_at: "now() - interval '7 years' - interval '1 day'")
        kept = insert_audit_log(owner, tenant, occurred_at: "now() - interval '7 years' + interval '1 day'")

        expect(owner.select_value("SELECT purge_expired_audit_logs()")).to eq(1)
        remaining = owner.select_values("SELECT id FROM audit_logs WHERE id IN (#{[ expired, kept ].map { owner.quote(_1) }.join(', ')})")
        expect(remaining).to eq([ kept ])
      end
    end

    # 一時表は search_path の先頭に来るので、表を修飾しない関数は同じ名前の一時表を消す
    it "保存期間を過ぎた行を消す関数は、同じ名前の一時表があっても監査ログの表を消す" do
      with_owner_rows do |tenant|
        expired = insert_audit_log(owner, tenant, occurred_at: "now() - interval '7 years' - interval '1 day'")
        owner.execute("CREATE TEMP TABLE audit_logs (occurred_at timestamptz) ON COMMIT DROP")
        owner.execute("INSERT INTO audit_logs VALUES (now() - interval '8 years')")

        expect(owner.select_value("SELECT purge_expired_audit_logs()")).to eq(1)
        expect(owner.select_value("SELECT count(*) FROM pg_temp.audit_logs")).to eq(1)
        expect(owner.select_value("SELECT count(*) FROM public.audit_logs WHERE id = #{owner.quote(expired)}")).to eq(0)
      end
    end
  end
end
