require "fileutils"

module Platform
  # メトリクスの値の置き場と exporter（docs/guides/config.md「メトリクス」）。exporter は Web とワーカーに 1 つずつ、
  # 環境変数 METRICS_PROCESS でプロセスの種類を示したプロセスでだけ立てる
  module Metrics
    PROCESSES = %w[web jobs].freeze
    QUEUE_GAUGES = %i[queue_ready_jobs queue_blocked_jobs queue_claimed_jobs queue_failed_jobs].freeze
    # 一度でも数えたキュー。収集のブロックは exporter の読み出しのスレッドで動くので、スレッドをまたいで使える集合にする
    COUNTED_QUEUES = Concurrent::Set.new

    class ConfigurationError < StandardError; end

    module_function

    # 値を書くプロセスの種類。無ければ exporter を立てず、値はプロセスのメモリに置く
    def process
      name = ENV["METRICS_PROCESS"].presence or return
      raise ConfigurationError, "METRICS_PROCESS は #{PROCESSES.join('・')} のどれかにする: #{name}" unless PROCESSES.include?(name)

      name
    end

    # 開発とテストの環境が同じ作業ツリーで動くので、環境ごとに分ける
    def directory(name) = Rails.root.join("tmp/metrics", Rails.env, name)

    # store はメトリクスを登録する時点で決まる（yabeda-prometheus 0.9.1 の lib/yabeda/prometheus/adapter.rb の store_settings）ので、
    # Yabeda の設定より前の初期化子で選ぶ。Puma と bin/jobs が fork した子のプロセスも同じディレクトリに書き、exporter がまとめて読む
    def use_file_store!
      name = process or return

      FileUtils.mkdir_p(directory(name))
      Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(dir: directory(name).to_s)
    end

    # Puma の起動のフックと SolidQueue.on_start が、fork の前に 1 回だけ呼ぶ。ディレクトリを空にするのもここだけにする。
    # 初期化子で空にすると、同じ設定で後から起きた別のプロセス（rake タスク・console）が、動いているプロセスの値を消す
    def start_exporter!(expected)
      return if Rails.env.test?

      name = process or return
      raise ConfigurationError, "このプロセスの METRICS_PROCESS は #{expected} にする: #{name}" unless name == expected
      # exporter はポートを PROMETHEUS_EXPORTER_PORT、無ければ PORT で決め、引数では渡せない（exporter.rb）。PORT は Puma も使う
      raise ConfigurationError, "exporter を立てるプロセスには PROMETHEUS_EXPORTER_PORT を設定する" if ENV["PROMETHEUS_EXPORTER_PORT"].blank?
      # Puma は puma.rb に workers が無くても、WEB_CONCURRENCY があればクラスタのモードで起きる（puma 8.0.2 の
      # lib/puma/configuration.rb の puma_options_from_env）。クラスタのモードの after_booted は worker を fork した後に動き、
      # ディレクトリを空にすると worker が書いている値を消す
      raise ConfigurationError, "Web の exporter は WEB_CONCURRENCY を設定しない Puma で立てる" if name == "web" && clustered_puma?

      FileUtils.rm_rf(directory(name).glob("*"))
      Yabeda::Prometheus::Exporter.start_metrics_server!
    end

    # SolidQueue.on_start が呼ぶ。solid_queue 1.7.0 の LifecycleHooks#run_hooks_for はフックの例外を Exception ごと拾って
    # 起動を続けるので、設定の誤りでは worker を fork する前にプロセスを終える。exit は SystemExit を上げ、同じく拾われる
    def start_worker_exporter!
      start_exporter!("jobs")
    rescue ConfigurationError => error
      warn "Platform::Metrics: #{error.message}"
      Kernel.exit!(1)
    end

    def clustered_puma?
      workers = ENV["WEB_CONCURRENCY"].to_s.strip
      workers == "auto" || workers.to_i.positive?
    end

    # 収集の時点で Solid Queue の表を数える。設定のキューと、一度でも数えたキューは、ジョブが無くても 0 を書く。
    # 書かないと、最後に数えた値が残る
    def collect_queue_depths
      counts = {
        queue_ready_jobs: SolidQueue::ReadyExecution.group(:queue_name).count,
        queue_blocked_jobs: SolidQueue::BlockedExecution.group(:queue_name).count,
        queue_claimed_jobs: SolidQueue::ClaimedExecution.joins(:job).group("solid_queue_jobs.queue_name").count,
        queue_failed_jobs: SolidQueue::FailedExecution.joins(:job).group("solid_queue_jobs.queue_name").count
      }
      queues = COUNTED_QUEUES.merge(counts.values.flat_map(&:keys)).to_a | configured_queues
      counts.each do |gauge, by_queue|
        queues.each { |queue| Yabeda.public_send(gauge).set({ queue: }, by_queue.fetch(queue, 0)) }
      end
    end

    def configured_queues
      Rails.application.config_for(:queue).fetch(:workers).flat_map { Array(_1[:queues]) }
    end
  end
end
