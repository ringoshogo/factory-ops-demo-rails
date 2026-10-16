require "rails_helper"
require Rails.root.join("lib/temp_databases").to_s

# 一時の DB の一覧と削除（lib/temp_databases.rb、docs/guides/config.md「database.yml：同じ DB に 2 つのロールで接続する」）。
# 消すのは、名前を明示した、名前の規則に合う一時の DB だけにする。誤ると、作者の開発の DB や rspec・E2E の既定の DB を消す。
# example は、自分で作った一時の DB だけを作って消し、ほかの担当の一時の DB に触れない
RSpec.describe TempDatabases do
  # 保守用の DB に所有ロールで接続する。DB の作成と削除はトランザクションの外で流す
  def maintenance
    config = ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "owner").configuration_hash
    PG.connect(host: config[:host], port: config[:port], user: config[:username], password: config[:password], dbname: "postgres")
  end

  def exists?(name)
    connection = maintenance
    connection.exec_params("SELECT 1 FROM pg_database WHERE datname = $1", [ name ]).ntuples == 1
  ensure
    connection&.close
  end

  describe ".temporary?" do
    it "factory_ops_ で始まり _test か _e2e を区切りとして含む名前だけを一時の DB とし、既定の 3 つは含めない" do
      temporary = %w[factory_ops_m51_test factory_ops_m51_e2e factory_ops_m33_review_test factory_ops_demo_rails_test_m30rev]
      kept = %w[
        factory_ops_demo_rails_development factory_ops_demo_rails_test factory_ops_e2e
        factory_ops_m49 factory_ops_m51_testing factory_ops_m51_e2ex other_m51_test postgres template1 factory_ops_M51_test
      ]

      expect((temporary + kept).select { described_class.temporary?(_1) }).to eq(temporary)
    end
  end

  describe ".list と .drop!" do
    let(:name) { "factory_ops_spec#{SecureRandom.hex(4)}_test" }

    before do
      connection = maintenance
      connection.exec("CREATE DATABASE #{connection.quote_ident(name)}")
    ensure
      connection&.close
    end

    after do
      connection = maintenance
      connection.exec("DROP DATABASE IF EXISTS #{connection.quote_ident(name)}")
    ensure
      connection&.close
    end

    it "一覧は一時の DB を接続の数と一緒に出し、既定の DB を出さない" do
      listed = described_class.list(env: "test").to_h

      expect(listed).to include(name => 0)
      expect(listed.keys & %w[factory_ops_demo_rails_development factory_ops_demo_rails_test factory_ops_e2e]).to eq([])

      config = ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "owner").configuration_hash
      held = PG.connect(host: config[:host], port: config[:port], user: config[:username], password: config[:password], dbname: name)
      expect(described_class.list(env: "test").to_h).to include(name => 1)
    ensure
      held&.close
    end

    it "名前を明示した一時の DB を消す。接続中なら消さずに PostgreSQL の失敗を出す" do
      config = ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "owner").configuration_hash
      held = PG.connect(host: config[:host], port: config[:port], user: config[:username], password: config[:password], dbname: name)
      expect { described_class.drop!(name, env: "test") }.to raise_error(PG::ObjectInUse, /is being accessed by other users/)
      expect(exists?(name)).to be(true)
      held.close

      described_class.drop!(name, env: "test")

      expect(exists?(name)).to be(false)
    ensure
      held&.close unless held&.finished?
    end

    it "名前が無いか、既定の DB か、名前の規則に合わないか、test の環境でなければ、消さずに止まる" do
      refused = [
        [ nil, "test" ], [ "", "test" ], [ "factory_ops_demo_rails_test", "test" ], [ "factory_ops_e2e", "test" ],
        [ "factory_ops_demo_rails_development", "test" ], [ "factory_ops_m49", "test" ], [ name, "development" ], [ name, "production" ]
      ]

      results = refused.map do |target, env|
        described_class.drop!(target, env:)
        :dropped
      rescue described_class::Refused
        :refused
      end

      expect(results).to eq([ :refused ] * refused.size)
      # 名前を渡し忘れた呼び出しには、規則に合わないとではなく、名前を明示するように返す
      expect { described_class.drop!(nil, env: "test") }.to raise_error(described_class::Refused, /名前を明示する/)
      expect(exists?(name)).to be(true)
      expect { described_class.list(env: "development") }.to raise_error(described_class::Refused, /test の環境/)
      expect { described_class.list(env: "production") }.to raise_error(described_class::Refused, /test の環境/)
    end
  end
end
