module Billing
  # 取引先ごとの請求条件（docs/architecture/data-model.md「請求（`billing`）」）
  module Terms
    # 締め日に許す値。29・30 は締め日の無い月があるので許さず、月末締めは 31 で表す
    CLOSING_DAYS = [ *1..28, BillingTerm::MONTH_END ].freeze

    def self.list(actor)
      Scope.call(actor, BillingTerm.all).order(:id).map { to_value(_1) }
    end

    # 取引先の請求条件を作り、あれば締め日を変える。取引先は、自社が受注側の取引関係（失効したものを含む）の相手に限る。
    # 失効の前の取引も請求まで進むからである。取引先の誤りは NOT_FOUND、締め日の誤りは INVALID_INPUT で、この順に確かめる
    def self.set(actor, customer_tenant_id:, closing_day:)
      unless Partnerships::Directory.customer?(actor, customer_tenant_id)
        return OperationResult.failure(:not_found, path: [ :customer_tenant_id ])
      end
      unless CLOSING_DAYS.include?(closing_day)
        return OperationResult.failure(:invalid_input, path: [ :closing_day ], message: "Closing day must be 1 to 28, or 31 for month end")
      end

      # 1 文の upsert にして、同じ取引先への同時の設定を一意索引で 1 行にまとめる。締めが行ロックを持つ間は、更新が待つ
      BillingTerm.upsert({ owner_tenant_id: actor.tenant_id, customer_tenant_id:, closing_day: },
        unique_by: %i[owner_tenant_id customer_tenant_id])
      term = Scope.call(actor, BillingTerm.all).find_by!(customer_tenant_id:)
      OperationResult.success(to_value(term))
    end

    def self.to_value(term) = BillingTermValue.new(**term.slice(*BillingTermValue.members.map(&:to_s)).symbolize_keys)
    private_class_method :to_value
  end
end
