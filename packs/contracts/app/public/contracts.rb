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
    Subscriptions.routes(event.class.name).each do |route|
      tenant_id = payload.fetch(route.tenant_key).presence or raise ArgumentError, "宛先テナントが空: #{route.tenant_key}"
      job = EventJob.perform_later(event.class.name, payload, route.receiver, tenant_id)
      raise ActiveJob::EnqueueError, "#{event.class.name} を #{route.receiver} へ登録できなかった" unless job.successfully_enqueued?
    end
  end
end
