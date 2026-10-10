module Mutations
  # 取引先を締め日で締め、締め日以前に検収された未請求明細をすべて集めた下書きの請求書を作る。
  # 入力と状態の結果は docs/architecture/data-model.md「請求（`billing`）」の表のとおり
  class CloseBillingPeriod < BaseMutation
    perspective :supplier
    authorize_with Billing::InvoicePolicy, :close?
    audit_exempt reason: "効果が自社の中で閉じる。請求書は確定するまで相手に届かない"

    argument :customer_tenant_id, ID
    argument :closing_date, GraphQL::Types::ISO8601Date
    result_field :invoice, Types::InvoiceType

    def perform(**input)
      Billing::Closing.close(current_user, **input)
    end
  end
end
