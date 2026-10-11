module Mutations
  # 下書きの請求書に請求番号を振って確定し、「請求書発行」を出す。発行済みは CONFLICT。
  # 入力と状態の結果は docs/architecture/data-model.md「請求（`billing`）」の表のとおり
  class IssueInvoice < BaseMutation
    perspective :supplier
    authorize_with Billing::InvoicePolicy, :issue?
    audit "invoice.issue", target: ->(target:, **) { target }, counterparty: ->(target:, **) { target.customer_tenant_id }

    argument :invoice_id, ID
    result_field :invoice, Types::InvoiceType

    # 自社の請求書だけを引く。見えない ID は NOT_FOUND になる
    def find_target(invoice_id:, **)
      Billing::Invoices.find(current_user, invoice_id)
    end

    def perform(target, **)
      Billing::Closing.issue(current_user, invoice_id: target.id)
    end
  end
end
