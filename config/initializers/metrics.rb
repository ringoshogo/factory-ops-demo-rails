require_relative "../../packs/platform/lib/platform/metrics"
require_relative "../../packs/platform/lib/platform/metrics_subscriber"

# メトリクスの定義（docs/guides/config.md「メトリクス」）。値は Platform::MetricsSubscriber が Rails.event のイベントから作る。
# ラベルにテナント ID・ユーザー ID・伝票の ID を入れない。テナントごとの調査はログの相関 ID で行う
Platform::Metrics.use_file_store!

Yabeda.configure do
  # バケットは SLO の閾値を境界に含める。指定しないと prometheus-client の既定（最大 10 秒）になり、60 秒・300 秒・900 秒の割合を
  # 取れない（docs/guides/config.md「メトリクスとラベル」）
  histogram :graphql_operation_duration_seconds, tags: %i[operation operation_type outcome],
    buckets: [ 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10 ], comment: "GraphQL の操作の時間"
  counter :graphql_top_level_errors_total, tags: %i[operation code reason], comment: "GraphQL のトップレベルのエラーの数"
  histogram :job_duration_seconds, tags: %i[queue job_class],
    buckets: [ 0.1, 0.5, 1, 5, 30, 60, 300, 900, 3600 ], comment: "ジョブの実行の時間"
  histogram :job_queue_latency_seconds, tags: %i[queue],
    buckets: [ 0.5, 1, 5, 15, 60, 300, 900 ], comment: "ジョブを登録してから実行が始まるまでの時間"
  histogram :event_delivery_lag_seconds, tags: %i[event],
    buckets: [ 1, 5, 15, 60, 300, 900 ], comment: "イベントを発行してから受け手が始まるまでの時間"
  counter :external_requests_total, tags: %i[provider status], comment: "外部のサービスへの要求の数"
  histogram :notification_acceptance_seconds, tags: %i[kind],
    buckets: [ 5, 30, 60, 300, 900, 3600 ], comment: "確実な通知の送信記録を作ってから送信先が受け付けるまでの時間"
  counter :notification_failures_total, tags: %i[kind reason], comment: "再試行しない失敗か再試行を使い切った確実な通知の数"
  counter :notification_dropped_total, tags: %i[kind reason], comment: "送るのをあきらめた撃ちっぱなしの通知の数"
  counter :import_rows_total, tags: %i[kind result], comment: "取り込みで結果を書いた行の数"
  histogram :import_duration_seconds, tags: %i[kind size],
    buckets: [ 10, 30, 60, 300, 900, 3600 ], comment: "取り込みを作ってから終えるまでの時間"

  # ゲージは supervisor の 1 つのプロセスだけが書く。DirectFileStore のゲージの既定の集計（:all）は pid のラベルを足すので、
  # 最後に書いた値を使う
  Platform::Metrics::QUEUE_GAUGES.each do |name|
    gauge name, tags: %i[queue], aggregation: :most_recent, comment: "Solid Queue の状態ごとのジョブの数"
  end
  # 収集のブロックは、どちらの exporter の読み出しでも動くので、ワーカーのプロセスだけに登録する
  if Platform::Metrics.process == "jobs"
    collect { Rails.application.executor.wrap { Platform::Metrics.collect_queue_depths } }
  end
end

operations = YAML.load_file(Rails.root.join("config/graphql_operations.yml"), symbolize_names: true)
Rails.event.subscribe(Platform::MetricsSubscriber.new(operations:))

# ワーカーの exporter は、supervisor が worker・dispatcher・scheduler を fork する前に 1 つだけ立てる
# （solid_queue 1.7.0 の README「Lifecycle hooks」）
SolidQueue.on_start { Platform::Metrics.start_worker_exporter! }
