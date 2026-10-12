require "json"

# E2E の世界の準備（lib/tasks/e2e.rake）。test の環境の E2E の DB を作り直し、Playwright のワーカーごとに DemoWorld の世界を
# 1 組ずつ作り、アカウントを JSON に書き出す。テストは自分のワーカーの世界のアカウントでログインし、他の世界に書かない。
#
# DemoWorld はジョブを claim せずにその場で流すので、世界を作る間に bin/jobs が動くと、同じジョブを両方が流しうる。
# Playwright は webServer を globalSetup より先に起こす（playwright 1.64 の lib/runner の createGlobalSetupTasks は、
# プラグインの setup の後に globalSetup を並べる）ので、準備は globalSetup に置けない。E2E の Rails を起こすスクリプト
# （frontend/e2e/start-rails.sh）が、この準備を終えてから bin/jobs を起こす。DB を作り直す前（e2e:check）と、世界を
# 作った後（e2e:prepare）に Solid Queue のプロセスが登録されていないことを確かめ、この順が崩れたら失敗する。
class E2ePrepare
  class Refused < StandardError; end

  # rspec のテスト DB を消さないように、E2E の DB の名前を明示したときだけ動く
  RSPEC_DATABASE = "factory_ops_demo_rails_test".freeze
  ACCOUNTS_PATH = Rails.root.join("tmp/e2e/worlds.json")

  def self.check_target!(env:, database:)
    raise Refused, "e2e:prepare は test の環境でだけ動く: #{env}" unless env == "test"
    return if database.present? && database != RSPEC_DATABASE

    raise Refused, "e2e:prepare は TEST_DATABASE に rspec のテスト DB と別の名前を渡したときだけ動く: #{database.inspect}"
  end

  # bin/jobs の supervisor・worker は solid_queue_processes に自分を登録し、心拍で時刻を書き直す。心拍が生きている登録が
  # あれば、ワーカーが動いている。強制終了したワーカーは登録を消さずに残すので、心拍が途絶えた登録は数えない
  # （solid_queue 1.7.0 の Process.prune と同じく process_alive_threshold で決める）
  def self.check_no_workers!(moment)
    count = SolidQueue::Process.where(last_heartbeat_at: SolidQueue.process_alive_threshold.ago..).count
    raise Refused, "e2e:prepare の#{moment}に Solid Queue のプロセスが #{count} 件ある。bin/jobs は準備を終えてから起こす" if count.positive?
  end

  def self.worlds(workers)
    raise ArgumentError, "ワーカーの数は 1 以上にする: #{workers}" unless workers.positive?

    Array.new(workers) do |index|
      result = DemoWorld.build(namespace: "w#{index}", variant: :e2e)
      { index:, accounts: result.accounts.map { _1.to_h.slice(:persona, :tenant, :role, :name, :email, :password) } }
    end
  end

  def self.write(worlds, path = ACCOUNTS_PATH)
    FileUtils.mkdir_p(path.dirname)
    path.write(JSON.pretty_generate(worlds))
  end
end
