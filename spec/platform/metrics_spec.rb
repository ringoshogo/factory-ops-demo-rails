require "rails_helper"
require "open3"

# メトリクスの値の置き場・exporter・キューの滞留の収集（docs/guides/config.md「メトリクス」）
RSpec.describe Platform::Metrics do
  def gauge(name, queue) = Prometheus::Client.registry.get(name).get(labels: { queue: })

  def with_env(values)
    previous = values.keys.to_h { [ _1, ENV[_1] ] }
    values.each { ENV[_1] = _2 }
    yield
  ensure
    previous.each { ENV[_1] = _2 }
  end

  describe ".start_exporter!" do
    before do
      allow(Rails.env).to receive(:test?).and_return(false)
      allow(Yabeda::Prometheus::Exporter).to receive(:start_metrics_server!)
    end

    let(:directory) { described_class.directory("web") }

    it "METRICS_PROCESS が合えば、ディレクトリを空にしてから exporter を立てる" do
      FileUtils.mkdir_p(directory)
      stale = directory.join("metric_spec___1.bin").tap { FileUtils.touch(_1) }

      with_env("METRICS_PROCESS" => "web", "PROMETHEUS_EXPORTER_PORT" => "9394") { described_class.start_exporter!("web") }

      expect(stale).not_to exist
      expect(Yabeda::Prometheus::Exporter).to have_received(:start_metrics_server!).once
    end

    it "METRICS_PROCESS が無いプロセスでは立てない" do
      with_env("METRICS_PROCESS" => nil, "PROMETHEUS_EXPORTER_PORT" => "9394") { described_class.start_exporter!("web") }

      expect(Yabeda::Prometheus::Exporter).not_to have_received(:start_metrics_server!)
    end

    it "PROMETHEUS_EXPORTER_PORT が無ければ、PORT を使わずに起動を止める" do
      with_env("METRICS_PROCESS" => "web", "PROMETHEUS_EXPORTER_PORT" => nil, "PORT" => "3000") do
        expect { described_class.start_exporter!("web") }.to raise_error(described_class::ConfigurationError, /PROMETHEUS_EXPORTER_PORT/)
      end
      expect(Yabeda::Prometheus::Exporter).not_to have_received(:start_metrics_server!)
    end

    it "METRICS_PROCESS がプロセスの種類と違えば、起動を止める" do
      with_env("METRICS_PROCESS" => "jobs", "PROMETHEUS_EXPORTER_PORT" => "9394") do
        expect { described_class.start_exporter!("web") }.to raise_error(described_class::ConfigurationError, /web/)
      end
    end

    it "METRICS_PROCESS が web と jobs のどちらでもなければ、起動を止める" do
      with_env("METRICS_PROCESS" => "worker", "PROMETHEUS_EXPORTER_PORT" => "9394") do
        expect { described_class.start_exporter!("web") }.to raise_error(described_class::ConfigurationError, /web・jobs のどれか/)
      end
    end

    it "Puma が WEB_CONCURRENCY でクラスタのモードなら、ディレクトリを空にせずに起動を止める" do
      FileUtils.mkdir_p(directory)
      kept = directory.join("metric_spec___1.bin").tap { FileUtils.touch(_1) }

      [ "2", "auto" ].each do |workers|
        with_env("METRICS_PROCESS" => "web", "PROMETHEUS_EXPORTER_PORT" => "9394", "WEB_CONCURRENCY" => workers) do
          expect { described_class.start_exporter!("web") }.to raise_error(described_class::ConfigurationError, /WEB_CONCURRENCY/)
        end
      end
      with_env("METRICS_PROCESS" => "web", "PROMETHEUS_EXPORTER_PORT" => "9394", "WEB_CONCURRENCY" => "0") do
        expect(kept).to exist
        described_class.start_exporter!("web")
      end
      expect(Yabeda::Prometheus::Exporter).to have_received(:start_metrics_server!).once
    ensure
      FileUtils.rm_rf(directory)
    end

    # solid_queue 1.7.0 はフックの例外を拾って起動を続けるので、ワーカーのフックはプロセスを終える
    it "ワーカーのフックは、設定の誤りで worker を fork する前にプロセスを終える" do
      allow(Kernel).to receive(:exit!)
      hook = SolidQueue::Supervisor.lifecycle_hooks.fetch(:start).sole

      with_env("METRICS_PROCESS" => "jobs", "PROMETHEUS_EXPORTER_PORT" => nil) do
        expect { hook.call(nil) }.to output(/PROMETHEUS_EXPORTER_PORT/).to_stderr
      end
      expect(Kernel).to have_received(:exit!).with(1)

      with_env("METRICS_PROCESS" => "jobs", "PROMETHEUS_EXPORTER_PORT" => "9395") { hook.call(nil) }
      expect(Kernel).to have_received(:exit!).once
      expect(Yabeda::Prometheus::Exporter).to have_received(:start_metrics_server!).once
    ensure
      FileUtils.rm_rf(described_class.directory("jobs"))
    end

    it "test の環境では、設定があっても立てない" do
      allow(Rails.env).to receive(:test?).and_call_original

      with_env("METRICS_PROCESS" => "web", "PROMETHEUS_EXPORTER_PORT" => "9394") { described_class.start_exporter!("web") }

      expect(Yabeda::Prometheus::Exporter).not_to have_received(:start_metrics_server!)
    end
  end

  describe ".collect_queue_depths" do
    before do
      stub_const("MetricsSpecJob", Class.new(ActiveJob::Base) do
        self.enqueue_after_transaction_commit = false
        def perform; end
      end)
    end

    # ジョブを登録して待機の実行を作り、別の状態にするときは待機の実行をその状態の実行に置き換える
    def enqueue(queue, state = nil)
      job_id = MetricsSpecJob.set(queue:).perform_later.provider_job_id
      return job_id unless state

      SolidQueue::ReadyExecution.where(job_id:).delete_all
      columns = { blocked: { queue_name: queue, concurrency_key: "k", expires_at: Time.current + 60 }, claimed: {}, failed: { error: "{}" } }
      "SolidQueue::#{state.capitalize}Execution".constantize.insert({ job_id:, created_at: Time.current, **columns.fetch(state) })
    end

    it "状態ごとのジョブをキューごとに数え、ジョブの無い設定のキューには 0 を書く" do
      2.times { enqueue("events") }
      enqueue("external_mail", :blocked)
      enqueue("imports", :claimed)
      enqueue("spec_queue", :failed)
      Yabeda.queue_claimed_jobs.set({ queue: "events" }, 7)
      Yabeda.queue_ready_jobs.set({ queue: "default" }, 5)

      described_class.collect_queue_depths

      aggregate_failures do
        expect(gauge(:queue_ready_jobs, "events")).to eq(2)
        expect(gauge(:queue_blocked_jobs, "external_mail")).to eq(1)
        expect(gauge(:queue_claimed_jobs, "imports")).to eq(1)
        expect(gauge(:queue_failed_jobs, "spec_queue")).to eq(1)
        expect(gauge(:queue_claimed_jobs, "events")).to eq(0)
        expect(gauge(:queue_ready_jobs, "default")).to eq(0)
      end
    end

    it "設定に無いキューは、ジョブが無くなった後の収集で 0 を書く" do
      job_id = enqueue("spec_temporary")
      described_class.collect_queue_depths
      expect(gauge(:queue_ready_jobs, "spec_temporary")).to eq(1)

      SolidQueue::ReadyExecution.where(job_id:).delete_all
      described_class.collect_queue_depths

      expect(gauge(:queue_ready_jobs, "spec_temporary")).to eq(0)
    end
  end

  # 本番と同じ DirectFileStore の経路を、METRICS_PROCESS を設定した子のプロセスで通す。テストのプロセスは値をメモリに置き、
  # METRICS_PROCESS が無いので収集のブロックを登録しない
  def collect_in_child(process)
    script = <<~RUBY
      require "./config/environment"
      Yabeda.collect!
      puts "SPEC_RESULT " + JSON.generate(
        store: Prometheus::Client.config.data_store.class.name,
        text: Prometheus::Client::Formats::Text.marshal(Prometheus::Client.registry)
      )
    RUBY
    output, status = Open3.capture2e({ "RAILS_ENV" => "test", "METRICS_PROCESS" => process }, RbConfig.ruby, "-e", script,
      chdir: Rails.root.to_s)
    expect(status).to be_success, output
    JSON.parse(output.lines.grep(/\ASPEC_RESULT /).sole.delete_prefix("SPEC_RESULT "))
  end

  it "METRICS_PROCESS=jobs のプロセスは、ファイルに書き、収集のブロックでキューのゲージを pid のラベル無しに書く" do
    directory = described_class.directory("jobs")
    FileUtils.rm_rf(directory)

    result = collect_in_child("jobs")

    expect(result.fetch("store")).to eq("Prometheus::Client::DataStores::DirectFileStore")
    expect(directory.glob("*.bin")).not_to be_empty
    expect(result.fetch("text").lines.grep(/\Aqueue_ready_jobs\{/)).to include(%(queue_ready_jobs{queue="events"} 0.0\n))
  ensure
    FileUtils.rm_rf(directory)
  end

  # Web の exporter もキューを数えると、同じキューの系列が 2 つの exporter から出て、合計が 2 倍になる
  it "METRICS_PROCESS=web のプロセスと、METRICS_PROCESS の無いプロセスは、収集のブロックを登録せず、キューのゲージを書かない" do
    directory = described_class.directory("web")

    result = collect_in_child("web")

    expect(result.fetch("store")).to eq("Prometheus::Client::DataStores::DirectFileStore")
    expect(result.fetch("text").lines.grep(/\Aqueue_ready_jobs\{/)).to eq([])
    expect(described_class.process).to be_nil
    expect(Yabeda.collectors).to be_empty
  ensure
    FileUtils.rm_rf(directory)
  end
end
