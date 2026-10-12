require "rails_helper"

# 構造化イベントからメトリクスを作る購読者と、メトリクスの定義（docs/guides/config.md「メトリクス」）。
# 値はプロセスの中で積み上がるので、example の前後の差で確かめる
RSpec.describe Platform::MetricsSubscriber do
  def metric(name) = Prometheus::Client.registry.get(name)

  def histogram_count(name, labels, le: "+Inf")
    metric(name)&.get(labels:)&.fetch(le) || 0
  end

  def counter_value(name, labels)
    metric(name)&.get(labels:) || 0
  end

  def operation_completed(**payload)
    Rails.event.notify("graphql.operation_completed", operation_name: "SupplierDashboard", operation_type: "query",
      result: "success", user_error_codes: [], error_codes: [], forbidden_reasons: [], duration_ms: 120.0, **payload)
  end

  describe "graphql.operation_completed" do
    it "graphql.operation_completed で graphql_operation_duration_seconds が増える" do
      labels = { operation: "SupplierDashboard", operation_type: "query", outcome: "ok" }

      expect { operation_completed }.to change { histogram_count(:graphql_operation_duration_seconds, labels) }.by(1)
    end

    it "時間はミリ秒を秒に直し、結果の種類を outcome に写す" do
      user_error = { operation: "PlacePurchaseOrder", operation_type: "mutation", outcome: "user_error" }
      error = { operation: "PlacePurchaseOrder", operation_type: "mutation", outcome: "error" }

      expect do
        operation_completed(operation_name: "PlacePurchaseOrder", operation_type: "mutation", result: "user_error", duration_ms: 400.0)
        operation_completed(operation_name: "PlacePurchaseOrder", operation_type: "mutation", result: "error", duration_ms: 600.0)
      end.to change { histogram_count(:graphql_operation_duration_seconds, user_error, le: "0.5") }.by(1)
        .and change { histogram_count(:graphql_operation_duration_seconds, error, le: "0.5") }.by(0)
        .and change { histogram_count(:graphql_operation_duration_seconds, error, le: "1") }.by(1)
    end

    it "登録していない操作名・名前の無い操作・種類の違う操作に付いた登録の名前は other になる" do
      query = { operation: "other", operation_type: "query", outcome: "ok" }
      mutation = { operation: "other", operation_type: "mutation", outcome: "ok" }

      expect do
        operation_completed(operation_name: "MyDashboard")
        operation_completed(operation_name: nil)
        operation_completed(operation_name: "SupplierDashboard", operation_type: "mutation")
        operation_completed(operation_name: "PlacePurchaseOrder", operation_type: "query")
      end.to change { histogram_count(:graphql_operation_duration_seconds, query) }.by(3)
        .and change { histogram_count(:graphql_operation_duration_seconds, mutation) }.by(1)
    end

    it "トップレベルのエラーをコードごとに数え、FORBIDDEN には出どころを、ほかのコードには none を付ける" do
      labels = ->(code, reason) { { operation: "SupplierDashboard", code:, reason: } }

      expect do
        operation_completed(result: "error", error_codes: %w[FORBIDDEN undefinedField FORBIDDEN none],
          forbidden_reasons: %w[object rule])
      end.to change { counter_value(:graphql_top_level_errors_total, labels.("FORBIDDEN", "object")) }.by(1)
        .and change { counter_value(:graphql_top_level_errors_total, labels.("FORBIDDEN", "rule")) }.by(1)
        .and change { counter_value(:graphql_top_level_errors_total, labels.("undefinedField", "none")) }.by(1)
        .and change { counter_value(:graphql_top_level_errors_total, labels.("none", "none")) }.by(1)
    end
  end

  describe "ジョブ" do
    it "active_job.completed で job_duration_seconds が増える。duration はミリ秒" do
      labels = { queue: "events", job_class: "Contracts::EventJob" }

      expect do
        Rails.event.notify("active_job.completed", job_class: "Contracts::EventJob", job_id: "j1", queue: "events", duration: 1500.0)
      end.to change { histogram_count(:job_duration_seconds, labels, le: "1") }.by(0)
        .and change { histogram_count(:job_duration_seconds, labels, le: "5") }.by(1)
    end

    it "active_job.started で、イベントの時刻から enqueued_at を引いた待ち時間を job_queue_latency_seconds に数える" do
      # イベントの時刻は Rails.event が実時間の時計で取るので、時刻を止めずに 3 秒前の登録にする
      enqueued_at = (Time.current - 3).utc.iso8601(9)

      expect do
        Rails.event.notify("active_job.started", job_class: "SpecJob", job_id: "j1", queue: "imports", enqueued_at:)
      end.to change { histogram_count(:job_queue_latency_seconds, { queue: "imports" }, le: "1") }.by(0)
        .and change { histogram_count(:job_queue_latency_seconds, { queue: "imports" }, le: "5") }.by(1)
    end

    it "登録を通らずに実行したジョブ（enqueued_at が無い）は数えない" do
      expect do
        Rails.event.notify("active_job.started", job_class: "SpecJob", job_id: "j1", queue: "imports", enqueued_at: nil)
      end.not_to change { histogram_count(:job_queue_latency_seconds, { queue: "imports" }) }
    end
  end

  it "contracts.event_handled で event_delivery_lag_seconds が増える" do
    labels = { event: "Contracts::PurchaseOrderPlaced" }

    expect do
      Rails.event.notify("contracts.event_handled", event_name: "Contracts::PurchaseOrderPlaced",
        receiver: "Sales::PurchaseOrderTranslator", delivery_lag_ms: 2000)
    end.to change { histogram_count(:event_delivery_lag_seconds, labels, le: "1") }.by(0)
      .and change { histogram_count(:event_delivery_lag_seconds, labels, le: "5") }.by(1)
  end

  describe "通知" do
    it "notifications.provider_responded で external_requests_total が増える" do
      expect do
        Rails.event.notify("notifications.provider_responded", provider: "sendgrid", status: "429")
      end.to change { counter_value(:external_requests_total, { provider: "sendgrid", status: "429" }) }.by(1)
    end

    it "notification.accepted で notification_acceptance_seconds が増える" do
      expect do
        Rails.event.notify("notification.accepted", kind: "received_invoice", delivery_id: "d1", attempts: 1, acceptance_ms: 20_000)
      end.to change { histogram_count(:notification_acceptance_seconds, { kind: "received_invoice" }, le: "5") }.by(0)
        .and change { histogram_count(:notification_acceptance_seconds, { kind: "received_invoice" }, le: "30") }.by(1)
    end

    it "送信の失敗と撃ちっぱなしの破棄を、種類と理由ごとに数える" do
      failed = { kind: "received_invoice", reason: "http_400" }
      dropped = { kind: "new_sales_order", reason: "retries_exhausted:http_503" }

      expect do
        Rails.event.notify("notification.delivery_failed", **failed, delivery_id: "d1", attempts: 1)
        Rails.event.notify("notification.best_effort_dropped", **dropped, attempts: 3)
      end.to change { counter_value(:notification_failures_total, failed) }.by(1)
        .and change { counter_value(:notification_dropped_total, dropped) }.by(1)
    end
  end

  describe "取り込み" do
    it "imports.chunk_applied で、反映した行と失敗した行を import_rows_total に足す" do
      expect do
        Rails.event.notify("imports.chunk_applied", kind: "items", import_id: "i1", applied_rows: 499, failed_rows: 1)
      end.to change { counter_value(:import_rows_total, { kind: "items", result: "applied" }) }.by(499)
        .and change { counter_value(:import_rows_total, { kind: "items", result: "failed" }) }.by(1)
    end

    it "imports.finished で import_duration_seconds が増え、10,000 行までと行を数える前の失敗を small、10,001 行からを large にする" do
      finished = ->(total_rows) do
        Rails.event.notify("imports.finished", kind: "stocks", import_id: "i1", result: "succeeded", total_rows:,
          applied_rows: total_rows, failed_rows: 0, duration_ms: 45_000)
      end

      expect { finished.(10_000) }
        .to change { histogram_count(:import_duration_seconds, { kind: "stocks", size: "small" }, le: "60") }.by(1)
        .and change { histogram_count(:import_duration_seconds, { kind: "stocks", size: "small" }, le: "30") }.by(0)
      expect { finished.(10_001) }.to change { histogram_count(:import_duration_seconds, { kind: "stocks", size: "large" }) }.by(1)
      expect { finished.(nil) }.to change { histogram_count(:import_duration_seconds, { kind: "stocks", size: "small" }) }.by(1)
    end
  end

  it "表に無いイベントでは、どのメトリクスも変わらない" do
    values = -> { Prometheus::Client.registry.metrics.to_h { [ _1.name, _1.values ] } }

    expect { Rails.event.notify("active_record.sql", sql: "SELECT 1") }.not_to change(&values)
  end

  describe "定義" do
    # SLO の閾値（docs/guides/config.md「メトリクスとラベル」）
    slo_thresholds = {
      graphql_operation_duration_seconds: [ 0.5, 1 ],
      event_delivery_lag_seconds: [ 60 ],
      notification_acceptance_seconds: [ 900 ],
      import_duration_seconds: [ 300 ]
    }

    slo_thresholds.each do |name, thresholds|
      thresholds.each do |threshold|
        it "#{name} の SLO の閾値 #{threshold} 秒がバケットの境界にあり、閾値ちょうどと閾値を超える値を別の le に数える" do
          histogram = metric(name)
          labels = histogram.labels.index_with { "spec-threshold" }
          le = threshold.to_s

          expect(histogram.buckets).to include(threshold)
          expect do
            histogram.observe(threshold, labels:)
            histogram.observe(threshold + 0.001, labels:)
          end.to change { histogram_count(name, labels, le:) }.by(1)
            .and change { histogram_count(name, labels) }.by(2)
        end
      end
    end

    it "どのメトリクスのラベルにも、テナント・ユーザー・_id で終わる名前が無い" do
      tags = Yabeda.metrics.values.flat_map(&:tags).uniq

      expect(tags).to include(:operation, :queue, :kind)
      expect(tags.grep(/tenant|user|_id\z/)).to eq([])
    end

    it "登録の表の queries と mutations は、画面の問い合わせ（frontend/graphql）の query と mutation の操作名と一致する" do
      registered = YAML.load_file(Rails.root.join("config/graphql_operations.yml"))
      screens = Rails.root.join("frontend/graphql").glob("*/*.graphql").map { GraphQL.parse(_1.read).definitions.sole }
        .group_by(&:operation_type).transform_values { |definitions| definitions.map(&:name) }

      expect(screens.fetch("query")).not_to be_empty
      expect(screens.fetch("mutation")).not_to be_empty
      expect(registered.fetch("queries")).to match_array(screens.fetch("query"))
      expect(registered.fetch("mutations")).to match_array(screens.fetch("mutation"))
    end
  end
end
