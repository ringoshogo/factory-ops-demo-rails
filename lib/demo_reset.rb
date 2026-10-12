# 公開の配置の毎日の作り直し（docs/adr/009 決定 3、deploy/README.md）。CronJob の daily-reset が bin/rails demo:reset で流す。
# 1. 本番の環境で DEMO_WORLD_ENABLED=1 が無ければ、Kubernetes の API も DB も触らずに止まる（Platform::DemoWorldGate）
# 2. web と jobs の Deployment を 0 にし、両方の Pod の一覧が空になるまで待つ。Deployment の status.replicas は終了中の Pod を
#    数えないので、Pod の一覧で待つ。消す DB に接続を残さず、DemoWorld がその場で流すジョブを bin/jobs に同時に流させない
# 3. 所有ロールで DB を消して作り直し、DemoWorld でシードの世界を作る
# 4. 成功しても失敗しても、web と jobs を 1 に戻す。作り直しに失敗した日も画面を止めないためである
class DemoReset
  class Refused < StandardError; end
  class Failed < StandardError; end

  DEPLOYMENTS = %w[web jobs].freeze
  # deploy/ の web と jobs の Pod のラベル
  POD_SELECTOR = "app in (web,jobs)".freeze
  # 終了の猶予（terminationGracePeriodSeconds の既定の 30 秒）を待っても余る長さにし、超えたら作り直さずに戻す
  POD_WAIT = 300
  # DB のタスクは子のプロセスで流す。rails 8.1 の db:prepare は、同じプロセスで既に接続を確かめた設定を初期化済みと見なし、
  # 作り直した DB に構造を読み込まずに終わる（lib/tasks/e2e.rake と同じ理由）
  DATABASE_COMMAND = %w[bin/rails db:drop db:prepare db:grant_app_role].freeze
  # activerecord 8.1 の DatabaseTasks.check_protected_environments! は、この変数があれば本番の環境の DB を消すタスクを止めない。
  # 子のプロセスにだけ渡し、このプロセスには立てない
  DATABASE_ENV = { "DISABLE_DATABASE_ENVIRONMENT_CHECK" => "1" }.freeze

  def self.run(**) = new(**).run

  def initialize(kubernetes: nil, out: $stdout, run_command: ->(env, *command) { system(env, *command, exception: true, chdir: Rails.root.to_s) },
    pod_wait: POD_WAIT, poll_interval: 2)
    @kubernetes = kubernetes
    @out = out
    @run_command = run_command
    @pod_wait = pod_wait
    @poll_interval = poll_interval
  end

  def run
    raise Refused, "本番の環境では DEMO_WORLD_ENABLED=1 のときだけ動く" unless Platform::DemoWorldGate.open?

    @kubernetes ||= Kubernetes.from_service_account
    completed = false
    begin
      result = reset
      completed = true
      result
    ensure
      restore(raise_on_failure: completed)
    end
  end

  private

  def reset
    DEPLOYMENTS.each { @kubernetes.scale(_1, 0) }
    wait_until_pods_gone
    say "Pod が無くなった。DB を作り直す"
    # 消す DB に自分の接続も残さない
    ActiveRecord::Base.connection_handler.clear_all_connections!
    @run_command.call(DATABASE_ENV, *DATABASE_COMMAND)
    result = DemoWorld.build(namespace: "", variant: :seed)
    say "デモのアカウント（パスワードはどれも #{result.accounts.first.password}）"
    result.accounts.each { say "  #{_1.persona.ljust(22)} #{_1.email}" }
    result
  end

  def wait_until_pods_gone
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @pod_wait
    loop do
      names = @kubernetes.pod_names(POD_SELECTOR)
      return if names.empty?
      raise Failed, "#{@pod_wait} 秒を過ぎても Pod が残っている: #{names.join('・')}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep @poll_interval
    end
  end

  # 片方に失敗しても、もう片方を戻す。作り直しが例外で終わったときは、その例外を上げるために戻せなかったことを書くだけにする
  def restore(raise_on_failure:)
    failed = DEPLOYMENTS.reject do |name|
      @kubernetes.scale(name, 1)
      true
    rescue StandardError => error
      say "#{name} を 1 に戻せなかった: #{error.message}"
      false
    end
    return if failed.empty?

    message = "#{failed.join('・')} を 1 に戻せなかった。kubectl scale deployment/#{failed.first} --replicas=1 で戻す（deploy/README.md）"
    raise Failed, message if raise_on_failure

    say message
  end

  def say(message) = @out.puts("demo:reset: #{message}")
end
