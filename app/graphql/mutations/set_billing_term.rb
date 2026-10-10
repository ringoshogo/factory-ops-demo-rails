module Mutations
  # 取引先の締め日を決める。取引先は自社が受注側の取引関係（失効したものを含む）の相手に限り、それ以外は NOT_FOUND。
  # 締め日は 1〜28 と月末の 31 だけで、外れれば INVALID_INPUT
  class SetBillingTerm < BaseMutation
    perspective :supplier
    authorize_with Billing::InvoicePolicy, :set_term?
    audit_exempt reason: "効果が自社の中で閉じる"

    argument :customer_tenant_id, ID
    argument :closing_day, Int
    result_field :billing_term, Types::BillingTermType

    def perform(**input)
      Billing::Terms.set(current_user, **input)
    end
  end
end
