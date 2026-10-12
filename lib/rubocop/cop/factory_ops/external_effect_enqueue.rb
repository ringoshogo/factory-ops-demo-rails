module RuboCop
  module Cop
    module FactoryOps
      # 外部へ作用するジョブの登録を、Notifications::Email（packs/notifications の公開 API）の 1 つのファイルに限る
      # （docs/adr/007 決定 4）。登録口の外から登録すると、送信記録と通知の種類の登録を通らずに外部へ作用する。
      # ExternalEffectJob のサブクラスは設定の Jobs に並べる。並べ漏れは spec/jobs/event_job_atomicity_spec.rb が落とす。
      # Action Mailer の deliver_later は ExternalEffectJob を継承しないジョブで送るので、受け手を問わず落とす
      #
      # @example
      #   # bad
      #   Notifications::CriticalDeliveryJob.perform_later(id)
      #   Notifications::Mailer.with(values:).received_invoice.deliver_later
      #
      #   # good
      #   Notifications::Email.deliver_critical(:received_invoice, key:, params:)
      class ExternalEffectEnqueue < Base
        JOB_MSG = "外部へ作用するジョブは Notifications::Email から登録する。"
        DELIVER_LATER_MSG = "deliver_later を使わない。通知は Notifications::Email から送る。"

        JOB_METHODS = %i[perform_later perform_now set new].freeze
        RESTRICT_ON_SEND = (JOB_METHODS + %i[deliver_later deliver_later!]).freeze

        def on_send(node)
          if %i[deliver_later deliver_later!].include?(node.method_name)
            add_offense(node, message: DELIVER_LATER_MSG)
          elsif node.receiver&.const_type? && external_effect_job?(node.receiver)
            add_offense(node, message: JOB_MSG)
          end
        end

        private

        # 名前空間の中で短い名前で書いた参照（CriticalDeliveryJob）も、最後の名前で照らす
        def external_effect_job?(const)
          name = const.source.delete_prefix("::")
          jobs.any? { |job| job == name || job.split("::").last == name }
        end

        def jobs = Array(cop_config["Jobs"])
      end
    end
  end
end
