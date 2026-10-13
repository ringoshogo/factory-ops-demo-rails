require "rails_helper"
require "open3"

# ログの出口と書式（docs/guides/config.md「ログ」）。テストの環境は、本番と同じ Platform::Logging.configure! を通る。
# 1 行のログは 1 件の JSON で、イベントごとに決めた項目だけを書き、値を文字列のまま書くフレームワークの経路を通さない
RSpec.describe "ログの出口と書式" do
  describe "構成" do
    it "文脈のミドルウェアは要求 ID を付けた後にあり、要求の開始と例外を文字列で書くミドルウェアは無い" do
      middlewares = Rails.application.middleware.map(&:klass)

      expect(middlewares.index(Platform::RequestContext)).to be > middlewares.index(ActionDispatch::RequestId)
      expect(middlewares.index(Platform::RequestContext)).to be > middlewares.index(ActionDispatch::Executor)
      expect(middlewares).not_to include(Rails::Rack::Logger, ActionDispatch::DebugExceptions)
    end

    it "params・ジョブの引数・例外のメッセージを文字列で書くフレームワークの購読を外している" do
      expect(ActiveSupport::LogSubscriber.log_subscribers.map(&:class)).not_to include(
        ActionController::LogSubscriber, ActionDispatch::LogSubscriber, ActiveJob::LogSubscriber, ActionMailer::LogSubscriber,
        SolidQueue::LogSubscriber
      )
    end

    # 依存を上げて購読やミドルウェアが増えたら落とし、値を文字列で書くかを読んでから一覧に足す（docs/guides/config.md「止めたフレームワークの文字列のログ」）。
    # 本番は全コードを先に読み込み、テストの環境と購読者の集合が違うので、子のプロセスで本番の環境を初期化して見る。
    # 直前の 2 つの example は、要求を流すテストの環境も同じ経路を止めていることを見る
    it "本番の環境の購読とミドルウェアの並びは、許した一覧と一致する" do
      script = <<~RUBY
        require "./config/application"
        Rails.application.initialize!
        puts "SPEC_RESULT " + JSON.generate(
          log_subscribers: ActiveSupport::LogSubscriber.log_subscribers.map { _1.class.name }.uniq.sort,
          event_subscribers: Rails.event.subscribers.map { _1[:subscriber].class.name },
          middlewares: Rails.application.middleware.map { _1.klass.to_s }
        )
      RUBY
      env = { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => "x", "RAILS_LOG_LEVEL" => nil }
      output, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, chdir: Rails.root.to_s)
      expect(status).to be_success, output
      production = JSON.parse(output.lines.grep(/\ASPEC_RESULT /).sole.delete_prefix("SPEC_RESULT "))

      aggregate_failures do
        expect(production.fetch("log_subscribers")).to eq(%w[
          ActionController::StructuredEventSubscriber
          ActionDispatch::StructuredEventSubscriber
          ActionMailer::StructuredEventSubscriber
          ActionView::LogSubscriber
          ActionView::StructuredEventSubscriber
          ActiveJob::StructuredEventSubscriber
          ActiveRecord::LogSubscriber
          ActiveRecord::StructuredEventSubscriber
        ])
        expect(production.fetch("event_subscribers")).to eq(%w[Platform::JsonLogSubscriber Platform::MetricsSubscriber])
        # AssumeSSL は要求を https として扱う印を env に書くだけで、ログを書かない（config/environments/production.rb の assume_ssl）
        expect(production.fetch("middlewares")).to eq(%w[
          ActionDispatch::AssumeSSL
          Rack::Sendfile
          ActionDispatch::Static
          ActionDispatch::Executor
          Rack::Runtime
          ActionDispatch::RequestId
          ActionDispatch::RemoteIp
          Rails::Rack::SilenceRequest
          Platform::RequestContext
          ActionDispatch::ShowExceptions
          ActionDispatch::Callbacks
          Rack::Head
          Rack::ConditionalGet
          Rack::ETag
          ActionDispatch::Cookies
          ActionDispatch::Session::CookieStore
        ])
      end
    end

    it "Rails.logger は、JSON の書式のロガーにだけ書き、タグを付けない" do
      expect(Rails.logger.broadcasts.map { _1.formatter.class }).to eq([ Platform::JsonLogFormatter ])
      expect(Rails.logger).not_to respond_to(:tagged)
    end

    it "Rails.event のイベントを、log/events.log の末尾に 1 行ずつ足す" do
      path = Rails.root.join("log/events.log")
      before = File.read(path)

      Rails.event.notify("spec.first")
      Rails.event.notify("spec.second")

      expect(File.read(path)).to start_with(before)
      expect(File.read(path).delete_prefix(before).lines.map { JSON.parse(_1)["name"] }).to eq(%w[spec.first spec.second])
    end

    it "ジョブの引数をログに書かない" do
      expect(ApplicationJob.log_arguments?).to be(false)
    end

    # SQL のバインド値や、JSON の解析に失敗した要求の本文は debug の水準で書かれる
    # 本番の水準の制限は、環境変数でも config.log_level の直接の指定でもなく、初期化の後の Rails.logger の水準で確かめる
    describe "本番の水準" do
      it "info より細かい水準のロガーを拒み、info 以上を許す" do
        logger = ->(level) { ActiveSupport::BroadcastLogger.new(Platform::Logging.build(StringIO.new).tap { _1.level = level }) }

        expect { Platform::Logging.verify_production_level!(logger.call(:debug)) }.to raise_error(ArgumentError, /debug/)
        expect { Platform::Logging.verify_production_level!(logger.call(:info)) }.not_to raise_error
      end

      # 子のプロセスで本番の環境を初期化し、Rails.logger の水準を返す。direct_level は production.rb の後の直接の指定
      def boot_production(log_level: nil, direct_level: nil)
        script = <<~RUBY
          require "./config/application"
          #{direct_level ? "Rails.application.initializer('spec.direct_level', before: :initialize_logger) { |app| app.config.log_level = :#{direct_level} }" : ""}
          Rails.application.initialize!
          print Rails.logger.level
        RUBY
        env = { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => "x", "RAILS_LOG_LEVEL" => log_level }
        Open3.capture2e(env, RbConfig.ruby, "-e", script, chdir: Rails.root.to_s)
      end

      it "本番の環境は、RAILS_LOG_LEVEL=debug でも config.log_level = :debug の直接の指定でも起動しない" do
        [ { log_level: "debug" }, { direct_level: "debug" } ].each do |setting|
          output, status = boot_production(**setting)
          expect(status).not_to be_success, "起動した: #{setting}"
          expect(output).to include("Platform::Logging")
        end
        expect(boot_production(log_level: "warn").first.lines.last).to eq("2")
      end
    end

    # ジョブの文脈の置き換えと戻し方（ApplicationJob#perform_now）は、文脈をスレッドごとに持つことを前提にする
    it "Rails の文脈の分離の単位はスレッドである" do
      expect(ActiveSupport::IsolatedExecutionState.isolation_level).to eq(:thread)
    end

    it "購読者の例外は、テストの環境では呼び出し元まで上がる" do
      expect(Rails.event.send(:raise_on_error?)).to be(true)
    end
  end

  describe "テストの後始末（spec/support/log_context.rb）" do
    # 後始末は example の後で走るので、中で別の example を走らせ、その後の文脈を見る。
    # group.run は実行の絞り込み（-e など）を内側の example にも掛けるので、example を直接走らせる
    it "example の中で設定したログとエラー通知の文脈は、次の example へ持ち越されない" do
      group = RSpec.describe("内側") do
        it("文脈を設定する") do
          Rails.event.set_context(request_id: "inner")
          Rails.error.set_context(tenant_id: "inner")
        end
      end
      RSpec.world.example_groups.delete(group)
      example = group.examples.sole

      example.run(group.new(example.inspect_output), RSpec::Core::NullReporter)

      expect(example.execution_result.status).to eq(:passed)
      expect(Rails.event.context).to eq({})
      expect(ActiveSupport::ExecutionContext.to_h).to eq({})
    end
  end

  describe "Platform::JsonLogFormatter" do
    it "Rails.logger の 1 行を 1 件の JSON にし、いまの文脈を context に入れる" do
      io = StringIO.new
      Rails.event.set_context(request_id: "req-1", tenant_id: "tenant-1")

      Platform::Logging.build(io).info("書いた")

      line = JSON.parse(io.string.lines.sole)
      expect(line).to include("level" => "INFO", "message" => "書いた",
        "context" => { "request_id" => "req-1", "tenant_id" => "tenant-1" })
      expect(Time.iso8601(line.fetch("time"))).to be_within(5.seconds).of(Time.current)
    end

    it "例外を渡されたら、メッセージを書かずにクラス名だけを書く" do
      io = StringIO.new

      Platform::Logging.build(io).error(ArgumentError.new("leak@example.com"))

      expect(io.string).not_to include("leak@example.com")
      expect(JSON.parse(io.string)).to include("message" => "ArgumentError")
    end
  end

  describe "Platform::JsonLogSubscriber" do
    let(:io) { StringIO.new }
    let(:subscriber) { Platform::JsonLogSubscriber.new(io) }

    def emit(name, payload)
      subscriber.emit(name:, payload:, tags: {}, context: { request_id: "req-1" }, timestamp: 1_700_000_000_123_456_789,
        source_location: { filepath: "/app/x.rb", lineno: 1, label: "x" })
      JSON.parse(io.string.lines.last)
    end

    it "1 件のイベントを、name・payload・tags・context・timestamp の 1 行にする" do
      line = emit("active_job.started", { job_class: "SpecJob", job_id: "j1", queue: "default", enqueued_at: "t" })

      expect(line).to eq("name" => "active_job.started",
        "payload" => { "job_class" => "SpecJob", "job_id" => "j1", "queue" => "default", "enqueued_at" => "t" },
        "tags" => {}, "context" => { "request_id" => "req-1" }, "timestamp" => "2023-11-14T22:13:20.123456Z")
    end

    it "要求の開始は params を書かない" do
      line = emit("action_controller.request_started",
        { controller: "SessionsController", action: "create", format: "JSON", params: { "email" => "leak@example.com" } })

      expect(line.fetch("payload")).to eq("controller" => "SessionsController", "action" => "create", "format" => "JSON")
    end

    it "GraphQL の要求の開始は、操作名・クエリの SHA-256 の要約・変数のキーの一覧に置き換える" do
      query = "query Leak { viewer { id } }"
      line = emit("action_controller.request_started",
        { controller: "GraphqlController", action: "execute", format: "JSON",
          params: { "query" => query, "operationName" => "Leak", "variables" => { "input" => { "reason" => "leak" } } } })

      expect(line.fetch("payload")).to eq("controller" => "GraphqlController", "action" => "execute", "format" => "JSON",
        "operation_name" => "Leak", "query_sha256" => Digest::SHA256.hexdigest(query), "variable_keys" => [ "input" ])
    end

    it "GraphQL の操作名と変数のキーは、GraphQL の名前の形の文字列だけを書く。ほかの型と形は、中の値ごと落とす" do
      lines = [ { "leak" => "LEAK" }, [ "LEAK" ], "LEAK value", "Place_1" ].map do |name|
        emit("action_controller.request_started", { controller: "GraphqlController", action: "execute", format: "JSON",
          params: { "operationName" => name, "variables" => { "input" => 1, "LEAK key" => 2, "_ok" => 3 } } })
      end

      expect(lines.map { _1.dig("payload", "operation_name") }).to eq([ nil, nil, nil, "Place_1" ])
      expect(lines.map { _1.dig("payload", "variable_keys") }).to all(eq(%w[input _ok]))
    end

    it "ヘルスチェックの要求は書かない" do
      %w[action_controller.request_started action_controller.request_completed].each do |name|
        subscriber.emit(name:, payload: { controller: "Rails::HealthController", action: "show" }, tags: {}, context: {},
          timestamp: 1)
      end

      expect(io.string).to be_empty
    end

    it "GraphQL の変数がハッシュでなければ、キーの一覧を空にする" do
      line = emit("action_controller.request_started",
        { controller: "GraphqlController", action: "execute", format: "JSON", params: { "variables" => "leak" } })

      expect(line.fetch("payload")).to include("operation_name" => nil, "query_sha256" => nil, "variable_keys" => [])
    end

    it "要求の終わりは、状態コードと時間を書き、表に無い項目を落とす" do
      line = emit("action_controller.request_completed",
        { controller: "GraphqlController", action: "execute", status: 200, duration_ms: 1.5, db_runtime: 0.4, leak: "x" })

      expect(line.fetch("payload")).to eq("controller" => "GraphqlController", "action" => "execute", "status" => 200,
        "duration_ms" => 1.5, "db_runtime" => 0.4)
    end

    it "rescue_from で扱った例外は、クラス名だけを書く" do
      line = emit("action_controller.rescue_from_handled",
        { exception_class: "ArgumentError", exception_message: "leak", exception_backtrace: "app/x.rb:1" })

      expect(line.fetch("payload")).to eq("exception_class" => "ArgumentError")
    end

    it "ジョブのイベントは、引数・例外のメッセージ・バックトレースを書かない" do
      line = emit("active_job.completed",
        { job_class: "SpecJob", job_id: "j1", queue: "default", adapter: "SolidQueue", aborted: nil, duration: 2.0,
          arguments: [ "leak" ], exception_class: "ArgumentError", exception_message: "leak", exception_backtrace: [ "leak" ] })

      expect(line.fetch("payload")).to eq("job_class" => "SpecJob", "job_id" => "j1", "queue" => "default",
        "adapter" => "SolidQueue", "aborted" => nil, "duration" => 2.0, "exception_class" => "ArgumentError")
    end

    it "再試行・破棄のイベントも、例外のメッセージを書かない" do
      retried = emit("active_job.retry_scheduled",
        { job_class: "SpecJob", job_id: "j1", executions: 1, wait_seconds: 3, exception_class: "E", exception_message: "leak" })
      discarded = emit("active_job.discarded",
        { job_class: "SpecJob", job_id: "j1", exception_class: "E", exception_message: "leak" })

      expect(retried.fetch("payload")).to eq("job_class" => "SpecJob", "job_id" => "j1", "executions" => 1, "wait_seconds" => 3,
        "exception_class" => "E")
      expect(discarded.fetch("payload")).to eq("job_class" => "SpecJob", "job_id" => "j1", "exception_class" => "E")
    end

    it "アプリが出すイベントは、定義した項目を書く" do
      operation = emit("graphql.operation_completed",
        { operation_name: "Place", operation_type: "mutation", result: "error", user_error_codes: [ "NOT_FOUND" ],
          error_codes: [ "FORBIDDEN" ], forbidden_reasons: [ "rule" ], duration_ms: 3.2 })
      handled = emit("contracts.event_handled",
        { event_name: "Contracts::PurchaseOrderPlaced", receiver: "Sales::PurchaseOrderTranslator", delivery_lag_ms: 12 })

      expect(operation.fetch("payload")).to eq("operation_name" => "Place", "operation_type" => "mutation", "result" => "error",
        "user_error_codes" => [ "NOT_FOUND" ], "error_codes" => [ "FORBIDDEN" ], "forbidden_reasons" => [ "rule" ], "duration_ms" => 3.2)
      expect(handled.fetch("payload")).to eq("event_name" => "Contracts::PurchaseOrderPlaced",
        "receiver" => "Sales::PurchaseOrderTranslator", "delivery_lag_ms" => 12)

      failed = emit("notification.delivery_failed",
        { kind: "received_invoice", delivery_id: "d1", reason: "http_400", attempts: 1, to: "leak@example.com" })
      dropped = emit("notification.best_effort_dropped",
        { kind: "new_sales_order", reason: "retries_exhausted:http_503", attempts: 3, to: "leak@example.com" })

      expect(failed.fetch("payload")).to eq("kind" => "received_invoice", "delivery_id" => "d1", "reason" => "http_400", "attempts" => 1)

      responded = emit("notifications.provider_responded", { provider: "sendgrid", status: "429", to: "leak@example.com" })
      accepted = emit("notification.accepted",
        { kind: "received_invoice", delivery_id: "d1", attempts: 2, acceptance_ms: 90_500, to: "leak@example.com" })

      expect(responded.fetch("payload")).to eq("provider" => "sendgrid", "status" => "429")
      expect(accepted.fetch("payload")).to eq("kind" => "received_invoice", "delivery_id" => "d1", "attempts" => 2,
        "acceptance_ms" => 90_500)
      expect(dropped.fetch("payload")).to eq("kind" => "new_sales_order", "reason" => "retries_exhausted:http_503", "attempts" => 3)

      chunk = emit("imports.chunk_applied", { kind: "items", import_id: "i1", applied_rows: 499, failed_rows: 1, filename: "顧客.csv" })
      finished = emit("imports.finished", { kind: "items", import_id: "i1", result: "partially_failed", total_rows: 500,
        applied_rows: 499, failed_rows: 1, duration_ms: 1200, filename: "顧客.csv" })

      expect(chunk.fetch("payload")).to eq("kind" => "items", "import_id" => "i1", "applied_rows" => 499, "failed_rows" => 1)
      expect(finished.fetch("payload")).to eq("kind" => "items", "import_id" => "i1", "result" => "partially_failed", "total_rows" => 500,
        "applied_rows" => 499, "failed_rows" => 1, "duration_ms" => 1200)
    end

    it "表に無いイベントは、name・context・timestamp だけを書く" do
      line = emit("active_record.sql", { sql: "SELECT 'leak'", binds: [ "leak" ] })

      expect(line.keys).to eq(%w[name context timestamp])
    end

    it "ハッシュでないペイロードは例外にする。filter_parameters が掛からないからである" do
      expect { emit("SpecEvent", Data.define(:email).new(email: "leak@example.com")) }
        .to raise_error(Platform::JsonLogSubscriber::NonHashPayload)
      expect(io.string).to be_empty
    end

    it "イベントのオブジェクトを Rails.event.notify に渡すと、呼び出し元で例外になる" do
      expect { Rails.event.notify(Data.define(:email).new(email: "leak@example.com")) }
        .to raise_error(Platform::JsonLogSubscriber::NonHashPayload)
    end
  end
end
