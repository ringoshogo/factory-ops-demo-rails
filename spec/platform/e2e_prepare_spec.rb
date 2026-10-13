require "rails_helper"
require "rake"
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

  describe ".worlds" do
    it "ワーカーごとに namespace w<番号> の世界を作り、そのアカウントを返す。ワーカーの数が 1 未満なら作らずに止まる" do
      expect { described_class.worlds(0) }.to raise_error(ArgumentError, /1 以上/)

      worlds = described_class.worlds(1)

      expect(worlds.map { _1[:index] }).to eq([ 0 ])
      expect(worlds.sole[:accounts].map { _1[:email] }).to all(include("+w0@"))
      expect(worlds.sole[:accounts].map { _1[:persona] }).to include("supplier_admin", "revoked_buyer_admin")
    end
  end

  # rake タスクが守りを呼ぶこと。守りの関数だけを確かめても、タスクから呼び出しを外したことは捕まらない
  describe "rake タスク" do
    before(:context) { Rails.application.load_tasks unless Rake::Task.task_defined?("e2e:check") }

    def with_env(values)
      previous = values.keys.to_h { [ _1, ENV[_1] ] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| ENV[key] = value }
    end

    def register_live_worker = SolidQueue::Process.register(kind: "Worker", pid: 12_346, name: "worker-e2e-task", hostname: "spec")

    it "e2e:check は、E2E の DB を指していないときと、心拍の生きているワーカーがいるときに止まる" do
      with_env("TEST_DATABASE" => "factory_ops_e2e") do
        expect { Rake::Task["e2e:check"].execute }.not_to raise_error
        register_live_worker
        expect { Rake::Task["e2e:check"].execute }.to raise_error(SystemExit).and output(/前に Solid Queue のプロセスが 1 件/).to_stderr
      end
      with_env("TEST_DATABASE" => nil) do
        expect { Rake::Task["e2e:check"].execute }.to raise_error(SystemExit).and output(/TEST_DATABASE/).to_stderr
      end
    end

    it "e2e:prepare は、世界を作った後に心拍の生きているワーカーがいれば、アカウントを書き出さずに止まる" do
      allow(described_class).to receive(:worlds) do
        register_live_worker
        []
      end
      expect(described_class).not_to receive(:write)

      with_env("TEST_DATABASE" => "factory_ops_e2e") do
        expect { Rake::Task["e2e:prepare"].execute(Rake::TaskArguments.new([ :workers ], [ "1" ])) }
          .to raise_error(SystemExit).and output(/後に Solid Queue のプロセスが 1 件/).to_stderr
      end
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
