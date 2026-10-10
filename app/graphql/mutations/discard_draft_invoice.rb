module Mutations
  # 下書きの請求書を消し、集めた明細を未請求に戻す。発行済みの請求書は CONFLICT
  class DiscardDraftInvoice < BaseMutation
    perspective :supplier
    authorize_with Billing::InvoicePolicy, :discard?
    audit_exempt reason: "効果が自社の中で閉じる"

    argument :invoice_id, ID
    # 請求書は消えるので、消した請求書の ID を返す
    result_field :discarded_invoice_id, ID

    # 自社の請求書だけを引く。見えない ID は NOT_FOUND になる
    def find_target(invoice_id:, **)
      Billing::Invoices.find(current_user, invoice_id)
    end

    def perform(target, **)
      Billing::Closing.discard(current_user, invoice_id: target.id)
    end
  end
end
