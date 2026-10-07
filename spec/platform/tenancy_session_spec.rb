require "rails_helper"

# セッションの SET で接続に残ったテナントが、次の利用者に漏れないことを確かめる（data-model.md「RLS」）。
# 例ごとのトランザクションの中では SET LOCAL がセッションの値を覆い隠し、接続も固定されて貸し出しが起きないので、使わない
RSpec.describe "セッションに残ったテナント" do
  self.use_transactional_tests = false

  let(:leaked_tenant) { SecureRandom.uuid }

  def tenant_setting(connection)
    connection.select_value("SELECT current_setting('app.tenant_id', true)")
  end

  it "Tenancy.with_tenant を抜けるときに空にする" do
    ApplicationRecord.with_connection do |connection|
      connection.execute("SET app.tenant_id = #{connection.quote(leaked_tenant)}")

      Tenancy.with_tenant(SecureRandom.uuid) { connection.select_value("SELECT 1") }

      expect(tenant_setting(connection)).to eq("")
      expect(connection.select_value("SELECT current_tenant_id()")).to be_nil
    end
  end

  context "接続の貸し出し" do
    # 接続が 1 本だけのプールを別に作り、返した接続がそのまま次に貸し出されるようにする
    let(:record_class) do
      stub_const("TenancySessionSpecRecord", Class.new(ActiveRecord::Base) { self.abstract_class = true }).tap do |klass|
        klass.establish_connection(ActiveRecord::Base.connection_db_config.configuration_hash.merge(max_connections: 1))
      end
    end
    let(:pool) { record_class.connection_pool }

    after { record_class.remove_connection }

    it "前の利用者が残したテナントを、次の貸し出しで空にする" do
      first = pool.checkout
      first.execute("SET app.tenant_id = #{first.quote(leaked_tenant)}")
      expect(tenant_setting(first)).to eq(leaked_tenant)
      pool.checkin(first)

      second = pool.checkout
      expect(second).to equal(first)
      expect(tenant_setting(second)).to eq("")
      expect(second.select_value("SELECT current_tenant_id()")).to be_nil
    ensure
      pool.checkin(second) if second
    end
  end
end
