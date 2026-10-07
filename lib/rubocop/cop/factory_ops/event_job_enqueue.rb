module RuboCop
  module Cop
    module FactoryOps
      # イベントのジョブの登録を Contracts.publish の 1 か所に限る（decisions.md 5 章「投入経路を Active Job 経由に限る」）。
      # 配送表を通らずに登録すると、宛先テナントと受け手の組を発行元が決めることになる。
      # SolidQueue::Job への直接の書き込みは、投入の時機の設定（docs/adr/005）が効かない
      #
      # @example
      #   # bad
      #   Contracts::EventJob.perform_later(name, payload, receiver, tenant_id)
      #   SolidQueue::Job.enqueue(job)
      #
      #   # good
      #   Contracts.publish(event)
      class EventJobEnqueue < Base
        EVENT_JOB_MSG = "Contracts::EventJob は Contracts.publish から登録する。"
        SOLID_QUEUE_MSG = "SolidQueue::Job に直接書かず、Active Job から登録する。"

        EVENT_JOB_METHODS = %i[perform_later perform_now set].freeze
        SOLID_QUEUE_METHODS = %i[enqueue enqueue_all new create create! insert insert! insert_all insert_all! upsert upsert_all].freeze
        RESTRICT_ON_SEND = (EVENT_JOB_METHODS + SOLID_QUEUE_METHODS).freeze

        # @!method event_job_enqueue?(node)
        def_node_matcher :event_job_enqueue?, <<~PATTERN
          (send {(const (const {nil? cbase} :Contracts) :EventJob) (const nil? :EventJob)} {#{EVENT_JOB_METHODS.map(&:inspect).join(' ')}} ...)
        PATTERN

        # @!method solid_queue_job_write?(node)
        def_node_matcher :solid_queue_job_write?, <<~PATTERN
          (send (const (const {nil? cbase} :SolidQueue) :Job) {#{SOLID_QUEUE_METHODS.map(&:inspect).join(' ')}} ...)
        PATTERN

        def on_send(node)
          if event_job_enqueue?(node)
            add_offense(node, message: EVENT_JOB_MSG)
          elsif solid_queue_job_write?(node)
            add_offense(node, message: SOLID_QUEUE_MSG)
          end
        end
      end
    end
  end
end
