require "rails_helper"
require Rails.root.join("lib/e2e_prepare").to_s

# E2E の世界の準備の守り（lib/e2e_prepare.rb）。準備は DB を作り直すので、rspec のテスト DB を指していれば止まる。
# 世界を作る間に bin/jobs が動くと同じジョブを両方が流すので、Solid Queue のプロセスが登録されていれば止まる
RSpec.describe E2ePrepare do
  describe ".check_target!" do
    it "test の環境で、rspec のテスト DB と別の名前を渡したときだけ通す" do
      expect { described_class.check_target!(env: "test", database: "factory_ops_e2e") }.not_to raise_error
    end

    it "test 以外の環境と、DB の名前が無いか rspec のテスト DB のときは止まる" do
      expect { described_class.check_target!(env: "development", database: "factory_ops_e2e") }.to raise_error(described_class::Refused, /test の環境/)
      expect { described_class.check_target!(env: "test", database: nil) }.to raise_error(described_class::Refused, /TEST_DATABASE/)
      expect { described_class.check_target!(env: "test", database: "factory_ops_demo_rails_test") }
        .to raise_error(described_class::Refused, /TEST_DATABASE/)
    end
  end

  describe ".check_no_workers!" do
    it "心拍の生きている Solid Queue のプロセスが無ければ通り、あれば止まる。心拍の途絶えた登録は数えない" do
      expect { described_class.check_no_workers!("後") }.not_to raise_error
      stale = SolidQueue::Process.register(kind: "Worker", pid: 12_344, name: "worker-e2e-stale", hostname: "spec")
      stale.update!(last_heartbeat_at: SolidQueue.process_alive_threshold.ago - 1.second)
      expect { described_class.check_no_workers!("後") }.not_to raise_error

      SolidQueue::Process.register(kind: "Worker", pid: 12_345, name: "worker-e2e-spec", hostname: "spec")

      expect { described_class.check_no_workers!("後") }.to raise_error(described_class::Refused, /後に Solid Queue のプロセスが 1 件/)
    end
  end

  it "書き出す JSON は、ワーカーごとの添字とアカウントを持つ" do
    path = Rails.root.join("tmp/e2e-spec-#{SecureRandom.hex(4)}.json")
    worlds = [ { index: 0, accounts: [ { persona: "supplier_admin", email: "admin+w0@seiran.example" } ] } ]
    described_class.write(worlds, path)

    expect(JSON.parse(path.read)).to eq([ { "index" => 0, "accounts" => [ { "persona" => "supplier_admin", "email" => "admin+w0@seiran.example" } ] } ])
  ensure
    path&.delete if path&.exist?
  end
end
