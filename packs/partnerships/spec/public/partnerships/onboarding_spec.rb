require "rails_helper"
require_relative "../../../../../spec/support/env_helpers"

# シードと E2E の世界の準備のためのテナントとユーザーの作成。ユーザーは作ったテナントの中でだけ書き、本番の環境では
# DEMO_WORLD_ENABLED=1 を渡したプロセスでだけ呼べる
# （docs/architecture/data-model.md「RLS」、docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
RSpec.describe Partnerships::Onboarding do
  include EnvHelpers

  let!(:other) { FactoryBot.create(:tenant) }
  let!(:stranger) { Tenancy.with_tenant(other.id) { FactoryBot.create(:user) } }
  let(:code) { "onboarding-#{SecureRandom.hex(4)}" }
  let(:users) do
    [ { email: "admin-#{code}@example.com", name: "管理者", role: "admin", password: "demo-password" },
      { email: "member-#{code}@example.com", name: "担当者", role: "member", password: "demo-password" } ]
  end

  def register(**overrides)
    described_class.register(name: "青嵐精機工業", code:, partner_code: SecureRandom.hex(16), users:, **overrides)
  end

  # アプリのロールの接続で、テナントを設定して生 SQL で読む。RLS が、設定したテナントの行だけを見せる
  def emails_seen_by(tenant_id)
    Tenancy.with_tenant(tenant_id) { ActiveRecord::Base.lease_connection.select_values("SELECT email FROM users ORDER BY email") }
  end

  describe ".register" do
    it "テナントと、そのテナントの admin と member を作り、テナントの ID を返す。ログインできる" do
      tenant_id = register

      expect(described_class.tenant_id(code:)).to eq(tenant_id)
      expect(emails_seen_by(tenant_id)).to eq(users.map { _1[:email] }.sort)
      login = Partnerships::Authentication.authenticate(email: users[0][:email], password: "demo-password")
      expect(login.tenant_id).to eq(tenant_id)
      expect(Tenancy.with_tenant(tenant_id) { Partnerships::Authentication.acting_user(login.user_id).role }).to eq("admin")
    end

    it "ユーザーを他社に書かない。所有テナントを渡すと、何も書かずに例外にする" do
      tenant_id = register
      # 対照：他社の設定の生 SQL は、他社のユーザーを読み、作ったユーザーを読まない
      expect(emails_seen_by(other.id)).to eq([ stranger.email ])

      expect { register(code: "#{code}-2", users: [ users[0].merge(email: "x-#{code}@example.com", owner_tenant_id: other.id) ]) }
        .to raise_error(ArgumentError)
      expect(emails_seen_by(other.id)).to eq([ stranger.email ])
      expect(described_class.tenant_id(code: "#{code}-2")).to be_nil
      expect(emails_seen_by(tenant_id)).to eq(users.map { _1[:email] }.sort)
    end

    it "既にあるテナントのコードと、既にあるメールアドレスは一意索引が拒み、テナントもユーザーも残さない" do
      expect { register(code: other.code) }.to raise_error(ActiveRecord::RecordNotUnique)
      expect { register(users: [ users[0].merge(email: stranger.email) ]) }.to raise_error(ActiveRecord::RecordNotUnique)

      expect(described_class.tenant_id(code:)).to be_nil
      expect(emails_seen_by(other.id)).to eq([ stranger.email ])
    end

    it "テナントの設定の中では呼べない" do
      expect { Tenancy.with_tenant(other.id) { register } }.to raise_error(ArgumentError, /テナントの設定の外/)
      expect(described_class.tenant_id(code:)).to be_nil
    end
  end

  describe "本番の環境" do
    before { allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production")) }

    it "DEMO_WORLD_ENABLED が無いか 1 でなければ、テナントを作らず、引きもせずに例外にする" do
      [ nil, "true" ].each do |value|
        with_env("DEMO_WORLD_ENABLED" => value) do
          expect { register }.to raise_error(Partnerships::Onboarding::ProductionEnvironment)
          expect { described_class.tenant_id(code: other.code) }.to raise_error(Partnerships::Onboarding::ProductionEnvironment)
        end
      end

      allow(Rails).to receive(:env).and_call_original
      expect(described_class.tenant_id(code:)).to be_nil
    end

    it "DEMO_WORLD_ENABLED=1 なら、テナントを作って引ける" do
      with_env("DEMO_WORLD_ENABLED" => "1") do
        tenant_id = register

        expect(described_class.tenant_id(code:)).to eq(tenant_id)
        expect(emails_seen_by(tenant_id)).to eq(users.map { _1[:email] }.sort)
      end
    end
  end
end
