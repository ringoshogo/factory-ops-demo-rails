require "rails_helper"
require "rake"
require_relative "../support/env_helpers"

# 公開の配置の毎日の作り直し（docs/adr/009 決定 3・決定 4）。Web とワーカーを 0 にして Pod が消えてから、所有ロールで DB を
# 作り直してデモの世界を作り、成功しても失敗しても 1 に戻す。Kubernetes の API は WebMock で受け、DB の作り直しのコマンドと
# DemoWorld は差し替える
RSpec.describe DemoReset do
  include EnvHelpers

  let(:api) { "https://kubernetes.test:6443" }
  let(:token) { Tempfile.new("token").tap { _1.write("spec-token"); _1.flush } }
  let(:kubernetes) { DemoReset::Kubernetes.new(base_url: api, token_path: token.path, namespace: "factory-ops-rails", ca_file: nil) }
  let(:events) { [] }
  let(:out) { StringIO.new }
  let(:account) { DemoWorld::Account.new(persona: "supplier_admin", tenant: "supplier", role: "admin", name: "", email: "a@example.com", password: "pw") }
  let(:commands) { [] }

  # Pod の一覧を、渡した配列の順に返す。最後の配列は何度でも返す。要素は名前か、[名前, phase] で、名前だけなら Running
  def stub_pods(*lists)
    remaining = lists.dup
    stub_request(:get, "#{api}/api/v1/namespaces/factory-ops-rails/pods")
      .with(query: { labelSelector: "app in (web,jobs)" }, headers: { "Authorization" => "Bearer spec-token" })
      .to_return do
        events << :pods
        pods = (remaining.size > 1 ? remaining.shift : remaining.first).map { Array(_1) }
        { status: 200, body: JSON.generate(items: pods.map { |name, phase| { metadata: { name: }, status: { phase: phase || "Running" } } }) }
      end
  end

  def stub_scale(name, replicas, status: 200)
    stub = stub_request(:patch, "#{api}/apis/apps/v1/namespaces/factory-ops-rails/deployments/#{name}/scale")
      .with(body: { spec: { replicas: } }.to_json, headers: { "Content-Type" => "application/merge-patch+json", "Authorization" => "Bearer spec-token" })
    return stub.to_timeout if status == :timeout

    stub.to_return { events << [ :scale, name, replicas ]; { status:, body: "{}" } }
  end

  # 別の作り直しが持っているのと同じロックを、別の接続で持つ
  def hold_reset_lock
    config = ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "owner").configuration_hash
    connection = PG.connect(host: config[:host], port: config[:port], user: config[:username], password: config[:password], dbname: "postgres")
    yield connection
  ensure
    connection&.close
  end

  def try_lock(connection) = connection.exec_params("SELECT pg_try_advisory_lock($1)", [ DemoReset::LOCK_KEY ]).getvalue(0, 0) == "t"

  def stub_all_scales
    %w[web jobs].product([ 0, 1 ]).each { stub_scale(*_1) }
  end

  # DB の作り直しのコマンド。子のプロセスに渡す環境変数と、そのときの自分のプロセスの環境変数を控える
  def run_command(result: true)
    lambda do |env, *command|
      events << :database
      commands << { env:, command:, own: ENV["DISABLE_DATABASE_ENVIRONMENT_CHECK"] }
      raise "db:prepare が失敗した" unless result
    end
  end

  def reset(run_command: self.run_command, pod_wait: 1)
    described_class.new(kubernetes:, out:, run_command:, pod_wait:, poll_interval: 0).run
  end

  before do
    allow(ActiveRecord::Base.connection_handler).to receive(:clear_all_connections!) { events << :release_connections }
    allow(DemoWorld).to receive(:build) do |**args|
      events << [ :demo_world, args ]
      DemoWorld::Result.new(tenant_ids: {}, accounts: [ account ])
    end
  end

  def production! = allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))

  describe "入口" do
    it "本番の環境で DEMO_WORLD_ENABLED が無いか 1 でなければ、Kubernetes の API も DB のタスクも呼ばずに例外で止まる" do
      production!
      stub_all_scales
      stub_pods([])
      expect(DemoReset::Kubernetes).not_to receive(:from_service_account)

      [ nil, "true" ].each do |value|
        with_env("DEMO_WORLD_ENABLED" => value) do
          expect { described_class.new(out:, run_command:).run }.to raise_error(DemoReset::Refused, /DEMO_WORLD_ENABLED/)
        end
      end

      expect(a_request(:any, /kubernetes\.test/)).not_to have_been_made
      expect(events).to eq([])

      # 対照：同じ準備で 1 を渡せば、API とコマンドを呼ぶ
      with_env("DEMO_WORLD_ENABLED" => "1") { reset }
      expect(events).to include(:database, [ :scale, "web", 0 ])
    end

    # 門（Platform::DemoWorldGate）は本番の環境の外では常に開くので、作り直しは本番の環境であることを自分で求める
    it "開発とテストの環境では、DEMO_WORLD_ENABLED=1 でも、ロックも Kubernetes の API も DB のタスクもシードも触らずに止まる" do
      stub_all_scales
      stub_pods([])
      allow(PG).to receive(:connect).and_call_original
      allow(DemoReset::Kubernetes).to receive(:from_service_account).and_call_original

      with_env("DEMO_WORLD_ENABLED" => "1") do
        %w[development test].each do |environment|
          allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new(environment))
          expect { described_class.new(out:, run_command:).run }.to raise_error(DemoReset::Refused, /本番の環境/)
        end
      end

      expect(PG).not_to have_received(:connect)
      expect(DemoReset::Kubernetes).not_to have_received(:from_service_account)
      expect(a_request(:any, /kubernetes\.test/)).not_to have_been_made
      expect(events).to eq([])

      # 対照：同じ準備で本番の環境なら、ロックを取り、API とコマンドとシードを呼ぶ
      production!
      with_env("DEMO_WORLD_ENABLED" => "1") { reset }
      expect(PG).to have_received(:connect)
      expect(events).to include([ :scale, "web", 0 ], :database, a_collection_starting_with(:demo_world))
    end
  end

  describe "作り直し" do
    # 入口を通る条件を与える。与えないと、どの example も入口で止まり、確かめたい振る舞いに届かない
    before { production! }
    around { |example| with_env("DEMO_WORLD_ENABLED" => "1") { example.run } }

    it "Web とワーカーを 0 にし、Pod の一覧が空になってから DB を作り直して世界を作り、1 に戻す" do
      stub_all_scales
      stub_pods(%w[web-1 jobs-1], %w[jobs-1], [])

      reset

      expect(events).to eq([
        [ :scale, "web", 0 ], [ :scale, "jobs", 0 ], :pods, :pods, :pods, :release_connections, :database,
        [ :demo_world, { namespace: "", variant: :seed } ], [ :scale, "web", 1 ], [ :scale, "jobs", 1 ]
      ])
      expect(out.string).to include("a@example.com")
    end

    it "本番の DB を消す確かめを外す変数は、作り直しのコマンドにだけ渡し、自分のプロセスには立てない" do
      stub_all_scales
      stub_pods([])

      reset

      expect(commands.sole).to eq(env: { "DISABLE_DATABASE_ENVIRONMENT_CHECK" => "1" },
        command: %w[bin/rails db:drop db:prepare db:grant_app_role], own: nil)
      expect(ENV).not_to have_key("DISABLE_DATABASE_ENVIRONMENT_CHECK")
    end

    it "作り直しが例外で終わっても、Web とワーカーを 1 に戻してから例外を上げる" do
      stub_all_scales
      stub_pods([])

      expect { reset(run_command: run_command(result: false)) }.to raise_error(RuntimeError, "db:prepare が失敗した")

      expect(events.last(2)).to eq([ [ :scale, "web", 1 ], [ :scale, "jobs", 1 ] ])
      expect(events).not_to include(a_collection_starting_with(:demo_world))
    end

    it "上限の時間を過ぎても Pod が残れば、DB を作り直さずに 1 に戻して失敗する" do
      stub_all_scales
      stub_pods(%w[jobs-1])

      expect { reset(pod_wait: 0) }.to raise_error(DemoReset::Failed, /jobs-1/)

      expect(events).not_to include(:database)
      expect(events.last(2)).to eq([ [ :scale, "web", 1 ], [ :scale, "jobs", 1 ] ])
    end

    it "0 にする途中で API が失敗しても、両方を 1 に戻す" do
      stub_scale("web", 0)
      stub_scale("jobs", 0, status: 403)
      stub_scale("web", 1)
      stub_scale("jobs", 1)

      expect { reset }.to raise_error(DemoReset::Failed, /403/)

      expect(events).not_to include(:database)
      expect(events.last(2)).to eq([ [ :scale, "web", 1 ], [ :scale, "jobs", 1 ] ])
    end

    it "作り直しが成功して 1 に戻せなければ、戻し方を添えて失敗する。戻せなかった 1 つのほかは戻す" do
      stub_scale("web", 0)
      stub_scale("jobs", 0)
      stub_scale("web", 1, status: 500)
      stub_scale("jobs", 1)
      stub_pods([])

      expect { reset }.to raise_error(DemoReset::Failed, /web.*kubectl scale/m)

      expect(events).to include([ :scale, "jobs", 1 ])
    end

    it "作り直しが例外で終わり、1 に戻す要求も時間切れになったら、作り直しの例外を上げ、戻し方をログに書く" do
      stub_scale("web", 0)
      stub_scale("jobs", 0)
      stub_scale("web", 1, status: :timeout)
      stub_scale("jobs", 1)
      stub_pods([])

      expect { reset(run_command: run_command(result: false)) }.to raise_error(RuntimeError, "db:prepare が失敗した")

      expect(events).to include([ :scale, "jobs", 1 ])
      expect(out.string).to match(/web を 1 に戻せなかった.*kubectl scale/m)
    end

    # CronJob の activeDeadlineSeconds を過ぎたときと Job を消したとき、kubelet は SIGTERM を送り、Ruby は SignalException を上げる
    it "作り直しの途中で SIGTERM を受けても、1 に戻してから終わる" do
      stub_all_scales
      stub_pods([])
      allow(DemoWorld).to receive(:build).and_raise(SignalException, "TERM")

      expect { reset }.to raise_error(SignalException)

      expect(events.last(2)).to eq([ [ :scale, "web", 1 ], [ :scale, "jobs", 1 ] ])
    end

    it "追い出された Pod と終わった Pod は、一覧に残っていても待たない" do
      stub_all_scales
      stub_pods([ %w[web-old Failed], %w[jobs-old Succeeded] ])

      reset(pod_wait: 0)

      expect(events).to include(:database)
    end

    it "所有ロールの DB 設定が無ければ、ロックも Kubernetes の API も DB のタスクも触らずに止まる" do
      stub_all_scales
      stub_pods([])
      allow(ActiveRecord::Base.configurations).to receive(:configs_for).and_wrap_original do |original, **options|
        options[:name] == "owner" ? nil : original.call(**options)
      end
      expect(PG).not_to receive(:connect)

      expect { reset }.to raise_error(DemoReset::Refused, /DB_OWNER_USER/)

      expect(a_request(:any, /kubernetes\.test/)).not_to have_been_made
      expect(events).to eq([])
    end

    it "ほかの作り直しがロックを持っていれば、Kubernetes の API も DB のタスクも呼ばずに止まる。終わればロックを外す" do
      stub_all_scales
      stub_pods([])

      hold_reset_lock do |other|
        expect(try_lock(other)).to be(true)
        expect { reset }.to raise_error(DemoReset::Refused, /ほかの作り直し/)
        expect(a_request(:any, /kubernetes\.test/)).not_to have_been_made
        expect(events).to eq([])
        other.exec_params("SELECT pg_advisory_unlock($1)", [ DemoReset::LOCK_KEY ])
      end

      # 対照：ロックが空いていれば作り直し、終わった後はほかの接続がロックを取れる
      reset
      expect(events).to include(:database)
      hold_reset_lock { |other| expect(try_lock(other)).to be(true) }
    end
  end

  describe "Kubernetes の API" do
    it "Pod の ServiceAccount のトークンと名前空間と CA を読み、API の Service の場所へ送る" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "token"), "spec-token")
        File.write(File.join(dir, "namespace"), "factory-ops-rails\n")
        env = { "KUBERNETES_SERVICE_HOST" => "kubernetes.test", "KUBERNETES_SERVICE_PORT" => "6443" }
        stub_pods(%w[web-1])

        client = DemoReset::Kubernetes.from_service_account(env, dir)

        expect(client.live_pod_names("app in (web,jobs)")).to eq(%w[web-1])
        expect(client.ca_file).to eq(File.join(dir, "ca.crt"))
      end
    end

    # 終了の猶予の間に、web と jobs を戻す 2 つの要求が終わる長さにする（deploy/daily-reset.yaml の terminationGracePeriodSeconds）
    it "要求の時間切れを、Net::HTTP の既定の 60 秒より短くする" do
      stub_pods([])
      expect(Net::HTTP).to receive(:start).with("kubernetes.test", 6443, hash_including(open_timeout: 5, read_timeout: 10)).and_call_original

      kubernetes.live_pod_names("app in (web,jobs)")
    end
  end

  # rake タスクが作り直しを呼び、入口で止まったら終了の状態を失敗にする
  describe "rake タスク" do
    before(:context) { Rails.application.load_tasks unless Rake::Task.task_defined?("demo:reset") }

    it "demo:reset は DemoReset.run を呼び、入口で止まったら失敗で終わる" do
      expect(described_class).to receive(:run)
      Rake::Task["demo:reset"].execute

      allow(described_class).to receive(:run).and_raise(DemoReset::Refused, "本番の環境で DEMO_WORLD_ENABLED=1 を渡したときだけ動く")
      expect { Rake::Task["demo:reset"].execute }.to raise_error(SystemExit).and output(/DEMO_WORLD_ENABLED/).to_stderr
    end
  end
end
