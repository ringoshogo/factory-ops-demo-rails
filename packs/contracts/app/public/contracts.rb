# コンテキスト間のイベントの置き場（docs/architecture/context-map.md「疎結合を守る規則」3・4）
module Contracts
  class OutsideTransaction < StandardError; end

  # 配送表の受け手ごとに EventJob を 1 件ずつ登録する。業務データを書くのと同じトランザクションの中で呼ぶ（docs/adr/005）。
  # EventJob の登録はここだけで行う（lib/rubocop/cop/factory_ops/event_job_enqueue.rb）
  def self.publish(event)
    unless ApplicationRecord.lease_connection.current_transaction.joinable?
      raise OutsideTransaction, "Contracts.publish はトランザクションの中で呼ぶ"
    end

    payload = event.to_payload
    metadata = event_metadata(event)
    Subscriptions.routes(event.class.name).each do |route|
      tenant_id = payload.fetch(route.tenant_key).presence or raise ArgumentError, "宛先テナントが空: #{route.tenant_key}"
      job = EventJob.new(event.class.name, payload, route.receiver, tenant_id)
      job.app_metadata = metadata.merge("tenant_id" => tenant_id)
      EventJob.publishing { job.enqueue }
      raise ActiveJob::EnqueueError, "#{event.class.name} を #{route.receiver} へ登録できなかった" unless job.successfully_enqueued?
    end
  end

  # イベントの付帯情報（docs/architecture/data-model.md「イベントの受け口と冪等キー」）。ペイロードにも引数にも入れない。
  # 受け手の中で発行すると、文脈の因果 ID は受け手が受け取ったイベントの ID なので、それが次のイベントの因果 ID になる。
  # 相関 ID の無い文脈（要求の外で公開 API を呼んだとき）では、このイベントから一連の処理が始まる
  def self.event_metadata(event)
    event_id = SecureRandom.uuid_v7
    context = Rails.event.context
    { "event_id" => event_id, "event_name" => event.class.name, "correlation_id" => context[:correlation_id] || event_id,
      "causation_id" => context[:causation_id], "source_tenant_id" => Current.tenant_id,
      "published_at" => Time.current.iso8601(6) }
  end
  private_class_method :event_metadata
end
