module Contracts
  # イベントを 1 つの受け手へ運ぶジョブ（docs/adr/005 決定 3）。Contracts.publish だけが登録する。
  # 受け手の排他は冪等キーと行ロックで取るので、limits_concurrency は付けない
  class EventJob < ApplicationJob
    class OutsidePublish < StandardError; end
    class TenantMismatch < StandardError; end

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

    def perform(event_name, payload, _receiver, _tenant_id)
      route.receiver.constantize.handle(event_name.constantize.from_payload(payload))
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

    def route
      event_name, _payload, receiver = arguments
      Subscriptions.routes(event_name).find { |r| r.receiver == receiver } or
        raise KeyError, "配送表に無い受け手: #{event_name} → #{receiver}"
    end
  end
end
