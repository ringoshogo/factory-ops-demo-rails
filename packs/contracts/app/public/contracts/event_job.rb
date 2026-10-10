module Contracts
  # イベントを 1 つの受け手へ運ぶジョブ（docs/adr/005 決定 3）。Contracts.publish だけが登録する。
  # 受け手の排他は冪等キーと行ロックで取るので、limits_concurrency は付けない
  class EventJob < ApplicationJob
    class OutsidePublish < StandardError; end
    class TenantMismatch < StandardError; end
    class MissingMetadata < StandardError; end

    # 受信の監査の行と配送の遅れの計測に使う付帯情報の項目。Contracts.publish がすべて入れる。
    # 無いジョブは受け手を動かさずに失敗させる。受け手の書き込みだけを残すと、相手テナントに効果が及ぶ書き込みが記録されない
    # （docs/guides/config.md「ログ」）
    REQUIRED_METADATA = %w[event_id event_name correlation_id source_tenant_id published_at].freeze

    PUBLISHING = :contracts_event_job_publishing
    private_constant :PUBLISHING

    # 業務データと同じトランザクションでジョブの行を書く
    self.enqueue_after_transaction_commit = false

    class << self
      # 登録の検査と宛先の決め方を上書きさせない
      def inherited(subclass)
        raise TypeError, "Contracts::EventJob は継承しない: #{subclass}"
      end

      # Contracts.publish が、配送表の受け手を登録する間だけ開く
      def publishing
        previous = Thread.current[PUBLISHING]
        Thread.current[PUBLISHING] = true
        yield
      ensure
        Thread.current[PUBLISHING] = previous
      end
    end

    def perform(event_name, payload, _receiver, tenant_id)
      started_at = Time.current
      missing = REQUIRED_METADATA - (app_metadata || {}).keys
      raise MissingMetadata, "付帯情報に #{missing.join('・')} が無い" if missing.any?

      route.receiver.constantize.handle(event_name.constantize.from_payload(payload))
      record_receipt(tenant_id)
      Rails.event.notify("contracts.event_handled", event_name:, receiver: route.receiver,
        delivery_lag_ms: delivery_lag_ms(started_at))
    end

    # 発行元のテナントではなく、宛先テナントの名義で受け手を動かす。宛先は引数を信じず、
    # 配送表の項目が指すペイロードの値から決め、引数の宛先テナントと食い違えば実行しない
    def perform_tenant_id
      tenant_id = arguments.fetch(1).fetch(route.tenant_key)
      raise TenantMismatch, "宛先テナントがペイロードの #{route.tenant_key} と違う" unless tenant_id == arguments.fetch(3)

      tenant_id
    end

    # 登録の経路（perform_later・enqueue・ActiveJob.perform_all_later）はどれもここを通る。
    # perform_all_later は enqueue のコールバックを呼ばないので、before_enqueue では止められない
    def serialize
      raise OutsidePublish, "Contracts::EventJob は Contracts.publish から登録する" unless Thread.current[PUBLISHING]

      super
    end

    private

    # 相手テナントが発行したイベントの受信を、受け手の書き込みと同じトランザクションで監査ログに書く
    # （docs/architecture/graphql-schema.md「監査ログ」）。同じテナントの中で受け渡すイベントは、相手に効果が及ばないので書かない
    def record_receipt(tenant_id)
      source_tenant_id = app_metadata.fetch("source_tenant_id")
      return if source_tenant_id == tenant_id

      AuditLog.record_receipt!(event_id: app_metadata.fetch("event_id"), event_name: app_metadata.fetch("event_name"),
        source_tenant_id:, correlation_id: app_metadata.fetch("correlation_id"))
    end

    # 配送の遅れ。発行時刻は付帯情報にある
    def delivery_lag_ms(started_at)
      ((started_at - Time.iso8601(app_metadata.fetch("published_at"))) * 1000).round
    end

    def route
      event_name, _payload, receiver = arguments
      Subscriptions.routes(event_name).find { |r| r.receiver == receiver } or
        raise KeyError, "配送表に無い受け手: #{event_name} → #{receiver}"
    end
  end
end
