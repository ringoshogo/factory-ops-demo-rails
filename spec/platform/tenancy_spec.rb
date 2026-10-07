require "rails_helper"
require_relative "../support/tenant_helpers"

# アプリのロール（RLS が掛かる一般ロール）で動かす。ロールの性質は spec/db/tenant_enforcement_spec.rb が確かめる
RSpec.describe Tenancy do
  include TenantHelpers

  let(:user_class) { stub_const("TenancySpecUser", Class.new(TenantRecord) { self.table_name = "users" }) }
  let!(:tenant_a) { create_tenant("a") }
  let!(:tenant_b) { create_tenant("b") }
  let!(:user_a) { described_class.with_tenant(tenant_a) { insert_user(tenant_a, "a@example.com") } }
  let!(:user_b) { described_class.with_tenant(tenant_b) { insert_user(tenant_b, "b@example.com") } }

  describe "テナント未設定" do
    it "TenantRecord のリレーションを作ると例外になる" do
      expect { user_class.all }.to raise_error(Tenancy::MissingTenant)
      expect { user_class.where(email: "a@example.com") }.to raise_error(Tenancy::MissingTenant)
    end

    it "find・find_by も例外になる（文のキャッシュを通っても）" do
      described_class.with_tenant(tenant_a) { user_class.find(user_a) }

      expect { user_class.find(user_a) }.to raise_error(Tenancy::MissingTenant)
      expect { user_class.find_by(email: "a@example.com") }.to raise_error(Tenancy::MissingTenant)
    end

    it "TenantRecord を保存すると例外になる" do
      user = described_class.with_tenant(tenant_a) { user_class.find(user_a) }

      expect { user.update!(name: "changed") }.to raise_error(Tenancy::MissingTenant)
      expect { user.destroy! }.to raise_error(Tenancy::MissingTenant)
    end

    it "生 SQL では 0 行になる" do
      expect(connection.select_value("SELECT count(*) FROM users")).to eq(0)
    end

    it "生 SQL の INSERT は RLS に拒否される" do
      expect { insert_user(tenant_a, "new@example.com") }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end
  end

  describe ".with_tenant" do
    it "ブロックの中では自社の行だけが見える" do
      described_class.with_tenant(tenant_a) do
        expect(Current.tenant_id).to eq(tenant_a)
        expect(tenant_setting).to eq(tenant_a)
        expect(connection.select_values("SELECT id FROM users")).to eq([ user_a ])
        expect(user_class.pluck(:id)).to eq([ user_a ])
      end
    end

    it "抜けた後は app.tenant_id が空に戻り、生 SQL が 0 行になる" do
      described_class.with_tenant(tenant_a) { connection.select_value("SELECT 1") }

      expect(tenant_setting).to eq("")
      expect(Current.tenant_id).to be_nil
      expect(connection.select_value("SELECT count(*) FROM users")).to eq(0)
    end

    it "例外で抜けた後も app.tenant_id が空に戻る" do
      expect { described_class.with_tenant(tenant_a) { raise "boom" } }.to raise_error("boom")

      expect(tenant_setting).to eq("")
      expect(connection.select_value("SELECT count(*) FROM users")).to eq(0)
    end

    it "テナントが空なら始めない" do
      expect { described_class.with_tenant(nil) { } }.to raise_error(ArgumentError)
    end
  end

  describe "入れ子の .with_tenant" do
    it "同じテナントなら、内側を抜けても外側のテナントが残る" do
      described_class.with_tenant(tenant_a) do
        described_class.with_tenant(tenant_a) { expect(user_class.pluck(:id)).to eq([ user_a ]) }

        expect(Current.tenant_id).to eq(tenant_a)
        expect(tenant_setting).to eq(tenant_a)
        expect(connection.select_values("SELECT id FROM users")).to eq([ user_a ])
      end
      expect(tenant_setting).to eq("")
    end

    it "別のテナントへの切り替えは例外になり、外側のテナントは変わらない" do
      described_class.with_tenant(tenant_a) do
        expect { described_class.with_tenant(tenant_b) { } }.to raise_error(Tenancy::TenantMismatch)

        expect(tenant_setting).to eq(tenant_a)
        expect(connection.select_values("SELECT id FROM users")).to eq([ user_a ])
      end
    end
  end

  describe "相手テナントの名義" do
    it "相手名義の INSERT は WITH CHECK に拒否される" do
      expect { described_class.with_tenant(tenant_a) { insert_user(tenant_b, "x@example.com") } }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
      expect {
        described_class.with_tenant(tenant_a) do
          user_class.create!(owner_tenant_id: tenant_b, email: "y@example.com", name: "y", role: "member")
        end
      }.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end

    it "自社の行を相手名義へ書き換える UPDATE は WITH CHECK に拒否される" do
      expect {
        described_class.with_tenant(tenant_a) do
          connection.update("UPDATE users SET owner_tenant_id = #{connection.quote(tenant_b)}")
        end
      }.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end

    it "相手の行への UPDATE・DELETE は 0 行になる" do
      described_class.with_tenant(tenant_a) do
        expect(connection.update("UPDATE users SET name = 'x' WHERE id = #{connection.quote(user_b)}")).to eq(0)
        expect(connection.delete("DELETE FROM users WHERE id = #{connection.quote(user_b)}")).to eq(0)
      end
      described_class.with_tenant(tenant_b) do
        expect(connection.select_value("SELECT name FROM users")).to eq("name")
      end
    end
  end
end
