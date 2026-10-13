require "rails_helper"
require "open3"

# 公開の配置のマニフェスト（deploy/、docs/adr/009）。リポジトリに Secret を置かず、所有ロールの資格情報とデモの世界の許可を
# 作り直しとマイグレーションの工程にだけ渡し、外へは画面だけを出す。deploy/*.yaml を読んで確かめる。
# 実機でしか確かめられないこと（メモリ・Tunnel・CronJob の時刻）は deploy/README.md の作者の手順にある
RSpec.describe "公開の配置のマニフェスト" do
  DEPLOY = Rails.root.join("deploy")
  WORKLOADS = %w[web jobs frontend migrate daily-reset].freeze
  # 作り直しが止めて戻す Deployment。Role・Pod のラベル・作り直しの定数を、それぞれこの値と比べる（docs/adr/009 決定 3）
  RESET_TARGETS = %w[web jobs].freeze

  # コンテナごとに渡す環境変数。値が文字列ならその値、:secret なら Secret から、:present なら値を問わず持つ、nil なら持たない
  # （docs/adr/009 決定 2〜5）
  ENV_TABLE = {
    "RAILS_ENV" => { "web" => "production", "jobs" => "production", "migrate" => "production", "daily-reset" => "production" },
    "SECRET_KEY_BASE" => { "web" => :secret, "jobs" => :secret, "migrate" => :secret, "daily-reset" => :secret },
    "DB_HOST" => { "web" => "postgres", "jobs" => "postgres", "migrate" => "postgres", "daily-reset" => "postgres" },
    "DB_PORT" => { "web" => "5432", "jobs" => "5432", "migrate" => "5432", "daily-reset" => "5432" },
    "DB_APP_USER" => { "web" => "factory_app", "jobs" => "factory_app", "migrate" => "factory_app", "daily-reset" => "factory_app" },
    "DB_APP_PASSWORD" => { "web" => :secret, "jobs" => :secret, "migrate" => :secret, "daily-reset" => :secret },
    "DB_OWNER_USER" => { "migrate" => "factory_owner", "daily-reset" => "factory_owner" },
    "DB_OWNER_PASSWORD" => { "migrate" => :secret, "daily-reset" => :secret },
    "RAILS_MAX_THREADS" => { "web" => "3", "jobs" => :present },
    "FRONTEND_ORIGIN" => { "web" => :present },
    "NOTIFICATIONS_PROVIDER" => { "web" => "file_system", "jobs" => "file_system", "daily-reset" => "file_system" },
    "DEMO_WORLD_ENABLED" => { "daily-reset" => "1" },
    "SHARED_DEMO_ACCOUNTS" => { "web" => "1" },
    "SOLID_QUEUE_SUPERVISOR_MODE" => { "jobs" => "async" },
    "RAILS_URL" => { "frontend" => "http://web:3000" }
  }.freeze

  def self.documents
    @documents ||= DEPLOY.glob("*.yaml").sort.reject { _1.basename.to_s == "kustomization.yaml" }.flat_map do |path|
      YAML.load_stream(path.read, filename: path.to_s).compact.map { _1.merge("_file" => path.basename.to_s) }
    end
  end

  def documents = self.class.documents
  def kustomization = YAML.load_file(DEPLOY.join("kustomization.yaml"))
  def find(kind, name) = documents.find { _1["kind"] == kind && _1.dig("metadata", "name") == name } || raise("#{kind}/#{name} が無い")
  def names_of(kind) = documents.select { _1["kind"] == kind }.map { _1.dig("metadata", "name") }.sort

  def pod_spec(document)
    document["kind"] == "CronJob" ? document.dig("spec", "jobTemplate", "spec", "template", "spec") : document.dig("spec", "template", "spec")
  end

  def workload(name) = documents.find { %w[Deployment Job CronJob].include?(_1["kind"]) && _1.dig("metadata", "name") == name }

  def workloads = documents.select { %w[Deployment Job CronJob].include?(_1["kind"]) }

  def containers(document) = pod_spec(document).values_at("initContainers", "containers").compact.flatten

  def main_container(name) = containers(workload(name)).sole

  def env_of(name) = main_container(name).fetch("env", []).to_h { [ _1["name"], _1 ] }

  # secretKeyRef と imagePullSecrets から、参照する Secret の名前とキーを、使うワークロードごとに集める。imagePullSecrets のキーは種類で決まる
  def secret_uses
    workloads.flat_map do |document|
      env_refs = containers(document).flat_map { _1.fetch("env", []) }.filter_map { _1.dig("valueFrom", "secretKeyRef") }
      pull = pod_spec(document).fetch("imagePullSecrets", []).map { { "name" => _1["name"], "key" => ".dockerconfigjson" } }
      (env_refs + pull).map { [ _1["name"], _1["key"], document.dig("metadata", "name") ] }
    end.uniq
  end

  def secret_refs = secret_uses.map { _1.first(2) }.uniq.sort

  it "kustomization.yaml が deploy/ のマニフェストをすべて並べ、名前空間を流用元と分ける" do
    expect(kustomization.fetch("resources").sort).to eq(documents.map { _1["_file"] }.uniq.sort)
    expect(kustomization.fetch("namespace")).to eq("factory-ops-rails")
    expect(find("Namespace", "factory-ops-rails")).to be_present
  end

  it "置くものは、計画の種類と名前のとおりである" do
    expect(names_of("Deployment")).to eq(%w[frontend jobs postgres web])
    expect(names_of("Service")).to eq(%w[frontend postgres web])
    expect(names_of("Ingress")).to eq(%w[frontend])
    expect(names_of("Job")).to eq(%w[migrate])
    expect(names_of("CronJob")).to eq(%w[daily-reset])
    expect([ names_of("ServiceAccount"), names_of("Role"), names_of("RoleBinding") ]).to all(eq(%w[daily-reset]))
    expect(names_of("PersistentVolumeClaim")).to eq(%w[postgres-data])
  end

  it "Secret をリポジトリに置かない" do
    expect(documents.map { _1["kind"] }).not_to include("Secret")
    # 手順書（README.md）は、作者が名前空間に Secret を入れるコマンドを書くので見ない
    manifests = DEPLOY.glob("**/*").select(&:file?).reject { _1.extname == ".md" }
    expect(manifests.map { _1.read.scan(/^\s*kind:\s*Secret\b/) }.flatten).to eq([])
  end

  it "すべてのコンテナが、CPU とメモリの requests と limits を持ち、limits は requests 以上である" do
    all = workloads.flat_map { |document| containers(document).map { [ document.dig("metadata", "name"), _1 ] } }

    expect(all.map(&:first).uniq.sort).to eq(%w[daily-reset frontend jobs migrate postgres web])
    all.each do |name, container|
      resources = container.fetch("resources", {})
      %w[cpu memory].each do |resource|
        requested, limited = resources.dig("requests", resource), resources.dig("limits", resource)
        expect([ requested, limited ]).to all(be_present), "#{name} の #{resource}"
        expect(quantity(limited)).to be >= quantity(requested), "#{name} の #{resource}"
      end
    end
  end

  def quantity(value)
    number = value.to_s[/\A[\d.]+/].to_f
    case value.to_s
    when /m\z/ then number / 1000
    when /Gi\z/ then number * 1024**3
    when /Mi\z/ then number * 1024**2
    else number
    end
  end

  # 既定の 1 秒では、Pi 4 で取り込みを流す間にプローブが時間切れになり、liveness が続けて落ちてコンテナが作り直されうる。
  # pg_isready は自分の待ち（-t）でも諦めるので、kubelet の時間切れより短くする
  it "すべてのプローブが、既定の 1 秒より長い時間切れ（timeoutSeconds）を明示し、pg_isready はその内に自分で終わる" do
    probes = workloads.flat_map do |document|
      containers(document).flat_map do |container|
        %w[startupProbe readinessProbe livenessProbe].filter_map { |kind| [ document.dig("metadata", "name"), kind, container[kind] ] if container[kind] }
      end
    end

    expect(probes.map { _1.first(2) }).to contain_exactly(
      %w[web startupProbe], %w[web readinessProbe], %w[web livenessProbe],
      %w[frontend readinessProbe], %w[frontend livenessProbe],
      %w[postgres readinessProbe], %w[postgres livenessProbe]
    )
    probes.each do |name, kind, probe|
      timeout = probe["timeoutSeconds"]
      expect(timeout).to be_a(Integer).and(be > 1), "#{name} の #{kind} の timeoutSeconds が #{timeout.inspect}"
      command = probe.dig("exec", "command")
      next unless command&.first == "pg_isready"

      wait = command.each_cons(2).find { |flag, _| flag == "-t" }&.last
      expect(wait && Integer(wait)).to be_between(1, timeout - 1), "#{name} の #{kind} の pg_isready -t が #{wait.inspect}"
    end
  end

  it "イメージはタグを固定し、latest を使わない。タグの無いイメージは kustomization.yaml の images でタグを決める" do
    images = kustomization.fetch("images").to_h { [ _1.fetch("name"), _1.fetch("newTag") ] }

    workloads.flat_map { containers(_1) }.each do |container|
      name, tag = container.fetch("image").split(":", 2)
      tag ||= images[name]
      expect(tag).to be_present, "#{container['image']} のタグが無い"
      expect(tag).not_to eq("latest")
    end
    expect(images.keys).to contain_exactly("ghcr.io/ringoshogo/factory-ops-demo-rails/api", "ghcr.io/ringoshogo/factory-ops-demo-rails/frontend")
  end

  describe "環境変数" do
    it "各コンテナが表の変数を持ち、表で持たないとした変数を持たない" do
      ENV_TABLE.each do |variable, expected|
        WORKLOADS.each do |name|
          entry = env_of(name)[variable]
          case expected[name]
          when nil then expect(entry).to be_nil, "#{name} が #{variable} を持つ"
          when :secret then expect(entry&.dig("valueFrom", "secretKeyRef")).to be_present, "#{name} の #{variable} が Secret から来ない"
          when :present then expect(entry&.fetch("value", nil)).to be_present, "#{name} が #{variable} を持たない"
          else expect(entry&.fetch("value", nil)).to eq(expected[name]), "#{name} の #{variable}"
          end
        end
      end
    end

    # async のモードでは全ワーカーが 1 つの接続プールを分け合う。ワーカーごとにスレッドとポーリングと心拍の接続を使い、
    # ディスパッチャ・スケジューラ・スーパーバイザがほかに使う（solid_queue 1.7.0 の README「Fork vs. async mode」）
    it "jobs の接続プールは、config/queue.yml のワーカーのスレッドに 2 ずつ足した和に 4 を足した数以上である" do
      queue = YAML.safe_load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true).fetch("production")
      required = queue.fetch("workers").sum { _1.fetch("threads") + 2 } + 4

      expect(Integer(env_of("jobs").dig("RAILS_MAX_THREADS", "value"))).to be >= required
    end

    it "PostgreSQL の max_connections は、web と jobs の接続プールと、migrate と daily-reset の既定のプール（5）の和より大きい" do
      args = main_container("postgres").fetch("args")
      max_connections = Integer(args.each_cons(2).find { _1 == "-c" && _2.start_with?("max_connections=") }.last.split("=").last)
      pools = %w[web jobs].sum { Integer(env_of(_1).dig("RAILS_MAX_THREADS", "value")) } + 5 * 2

      expect(max_connections).to be > pools
    end

    # 守るのは変数の名前ではなく、所有ロールのパスワードの Secret のキーを誰が読むかである。envFrom は Secret の全キーを渡すので使わない
    it "所有ロールのパスワードを読むのは、postgres（ロールを作る）と migrate と daily-reset だけで、envFrom を使うコンテナは無い" do
      readers = secret_uses.select { |name, key, _| name == "db-credentials" && key == "owner-password" }.map(&:last)

      expect(readers).to contain_exactly("postgres", "migrate", "daily-reset")
      expect(workloads.flat_map { containers(_1) }.select { _1.key?("envFrom") }).to eq([])
    end

    it "作り直しのほかのコンテナは、ServiceAccount のトークンを持たない" do
      workloads.each do |document|
        name = document.dig("metadata", "name")
        expect(pod_spec(document)["automountServiceAccountToken"]).to eq(name == "daily-reset"), name
      end
      expect(pod_spec(workload("daily-reset"))["serviceAccountName"]).to eq("daily-reset")
    end
  end

  it "Ingress は frontend だけで、Service はどれも ClusterIP である。公開のホスト名と FRONTEND_ORIGIN は kustomization.yaml の 1 つの値から入る" do
    ingress = find("Ingress", "frontend")
    expect(ingress.dig("spec", "rules").flat_map { _1.dig("http", "paths") }.map { _1.dig("backend", "service", "name") }).to eq(%w[frontend])
    expect(documents.select { _1["kind"] == "Service" }.map { _1.dig("spec", "type") || "ClusterIP" }).to all(eq("ClusterIP"))

    host = kustomization.fetch("configMapGenerator").sole.fetch("literals").sole[/\Ahost=(.+)\z/, 1]
    expect(host).to be_present
    targets = kustomization.fetch("replacements").sole.fetch("targets").to_h { [ _1.dig("select", "kind"), _1 ] }
    expect(targets.keys).to contain_exactly("Ingress", "Deployment")
    expect(targets["Ingress"].fetch("fieldPaths")).to eq([ "spec.rules.0.host" ])
    expect(targets["Deployment"].dig("select", "name")).to eq("web")
    expect(targets["Deployment"].fetch("fieldPaths")).to eq([ "spec.template.spec.containers.[name=web].env.[name=FRONTEND_ORIGIN].value" ])
    expect(env_of("web").dig("FRONTEND_ORIGIN", "value")).to start_with("https://")
  end

  # 18 のイメージはデータを /var/lib/postgresql/18/docker に置く。16 の置き場（/var/lib/postgresql/data）に付けると、データが PVC の外に残る
  it "postgres は 18 の小版まで固定したイメージで、PVC を /var/lib/postgresql に付け、Recreate で掴む" do
    postgres = find("Deployment", "postgres")
    container = main_container("postgres")
    volume = pod_spec(postgres).fetch("volumes").find { _1.dig("persistentVolumeClaim", "claimName") == "postgres-data" }

    expect(container.fetch("image")).to match(/\Apostgres:18\.\d+\z/)
    expect(container.fetch("volumeMounts").find { _1["name"] == volume["name"] }.fetch("mountPath")).to eq("/var/lib/postgresql")
    expect(postgres.dig("spec", "strategy", "type")).to eq("Recreate")
    pvc = find("PersistentVolumeClaim", "postgres-data")
    expect(pvc.dig("spec", "storageClassName")).to eq("local-path")
    expect(pvc.dig("spec", "accessModes")).to eq(%w[ReadWriteOnce])
  end

  # 所有ロールが業務の DB を db:prepare で作り、持ち主になる。作り直しで所有ロールが DB を消せるようにするためである
  it "postgres の初期化は、docker/initdb/01_roles.sql と同じ属性で 2 つのロールを作り、業務の DB を作らない" do
    attributes = ->(sql) { sql.scan(/CREATE ROLE\s+\S+\s+([A-Z ]+?)\s+PASSWORD/).flatten.map(&:split).map(&:sort) }
    script = find("ConfigMap", "postgres-initdb").fetch("data").values.join

    expect(attributes.call(script)).to eq(attributes.call(Rails.root.join("docker/initdb/01_roles.sql").read))
    expect(attributes.call(script).size).to eq(2)
    expect(script).not_to match(/CREATE DATABASE/i)
    expect(env_of("postgres")).not_to have_key("POSTGRES_DB")
  end

  it "daily-reset は日本時間で動き、重ねず、再試行せず、時間の上限を持ち、demo:reset を流す" do
    cron = find("CronJob", "daily-reset")
    job = cron.dig("spec", "jobTemplate", "spec")

    expect(cron.dig("spec", "timeZone")).to eq("Asia/Tokyo")
    expect(cron.dig("spec", "concurrencyPolicy")).to eq("Forbid")
    expect(cron.dig("spec", "startingDeadlineSeconds")).to be_a(Integer)
    expect(job.fetch("backoffLimit")).to eq(0)
    expect(job.fetch("activeDeadlineSeconds")).to be_a(Integer)
    expect(main_container("daily-reset").fetch("args")).to eq(%w[bin/rails demo:reset])
    expect(main_container("migrate").fetch("args")).to eq(%w[bin/rails db:prepare db:grant_app_role])
  end

  # 止められたときの猶予の間に、web と jobs を 1 に戻す 2 つの要求が時間切れまで掛かっても終わる
  it "daily-reset の終了の猶予は、Kubernetes の API の 2 つの要求の時間切れの和より長い" do
    grace = pod_spec(find("CronJob", "daily-reset")).fetch("terminationGracePeriodSeconds")

    expect(grace).to be > RESET_TARGETS.size * (DemoReset::Kubernetes::OPEN_TIMEOUT + DemoReset::Kubernetes::READ_TIMEOUT)
  end

  it "daily-reset の Role は、web と jobs の Deployment の get と scale の get・patch、Pod の list だけを許す" do
    rules = find("Role", "daily-reset").fetch("rules").map { _1.transform_values { |value| value.is_a?(Array) ? value.sort : value } }

    expect(rules).to contain_exactly(
      { "apiGroups" => [ "apps" ], "resources" => [ "deployments" ], "resourceNames" => RESET_TARGETS.sort, "verbs" => [ "get" ] },
      { "apiGroups" => [ "apps" ], "resources" => [ "deployments/scale" ], "resourceNames" => RESET_TARGETS.sort, "verbs" => %w[get patch] },
      { "apiGroups" => [ "" ], "resources" => [ "pods" ], "verbs" => [ "list" ] }
    )
    binding = find("RoleBinding", "daily-reset")
    expect(binding.fetch("roleRef")).to include("kind" => "Role", "name" => "daily-reset")
    expect(binding.fetch("subjects")).to eq([ { "kind" => "ServiceAccount", "name" => "daily-reset" } ])
  end

  # 作り直しが止める Deployment と、Pod の一覧を引くラベルで、web と jobs の Pod が両方そろって引ける
  it "作り直しは web と jobs を止め、その 2 つの Pod は作り直しが待つラベル（DemoReset::POD_SELECTOR）を持つ" do
    expect(DemoReset::DEPLOYMENTS).to eq(RESET_TARGETS)
    expect(DemoReset::POD_SELECTOR[/\Aapp in \((.+)\)\z/, 1].split(",")).to eq(RESET_TARGETS)
    RESET_TARGETS.each { expect(workload(_1).dig("spec", "template", "metadata", "labels", "app")).to eq(_1) }
  end

  it "deploy/README.md の Secret の表と deploy/preflight.sh が集めるものが、マニフェストの参照する Secret の名前とキーと、使うワークロードと一致する" do
    section = DEPLOY.join("README.md").read[/^## Secret\n(.*?)(?=^## )/m, 1].to_s
    rows = section.lines.grep(/\A\| `/).map { _1.split("|")[1, 3].map(&:strip) }
    table = rows.to_h { |name, key, users| [ [ name.delete("`"), key.delete("`") ], users.split("・").sort ] }
    uses = secret_uses.group_by { _1.first(2) }.transform_values { |list| list.map(&:last).sort }

    expect(secret_refs).not_to be_empty
    expect(table.keys.sort).to eq(secret_refs)
    expect(table).to eq(uses)
    output, status = Open3.capture2e(DEPLOY.join("preflight.sh").to_s, "--list")
    expect(status).to be_success, output
    expect(output.lines.grep(/\A  - /).map { _1.strip.delete_prefix("- ").split(" ", 2) }.sort).to eq(secret_refs)
  end
end
