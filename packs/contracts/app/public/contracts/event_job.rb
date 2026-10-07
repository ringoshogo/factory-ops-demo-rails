module Contracts
  # イベントを 1 つの受け手へ運ぶジョブ（docs/adr/005 決定 3）。Contracts.publish だけが登録する。
  # 受け手の排他は冪等キーと行ロックで取るので、limits_concurrency は付けない
  class EventJob < ApplicationJob
    # 業務データと同じトランザクションでジョブの行を書く。サブクラスも上書きしない
    self.enqueue_after_transaction_commit = false

    def perform(event_name, payload, receiver, _tenant_id)
      route = Subscriptions.routes(event_name).find { |r| r.receiver == receiver } or
        raise KeyError, "配送表に無い受け手: #{event_name} → #{receiver}"

      route.receiver.constantize.handle(event_name.constantize.from_payload(payload))
    end

    # 発行元のテナントではなく、宛先テナントの名義で受け手を動かす
    def perform_tenant_id
      arguments.fetch(3)
    end
  end
end
