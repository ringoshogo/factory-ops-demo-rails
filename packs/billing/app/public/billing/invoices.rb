module Billing
  # 受注側が自社の請求書を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）
  module Invoices
    def self.list(actor, first:, after:)
      Page.of(Scope.call(actor, Invoice.all), first:, after:) { |invoices| invoices.map { to_value(_1) } }
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.find(actor, id)
      Scope.call(actor, Invoice.where(id:)).first&.then { to_value(_1) }
    end

    # 請求書 ID ごとの税率ごとの集計。税率の昇順に並べ、見えない請求書の ID は空の配列になる
    def self.tax_summaries_for(actor, invoice_ids)
      summaries = Scope.call(actor, InvoiceTaxSummary.where(invoice_id: invoice_ids)).order(:invoice_id, :tax_rate_percent).map do |summary|
        InvoiceTaxSummaryValue.new(**summary.slice(*InvoiceTaxSummaryValue.members.map(&:to_s)).symbolize_keys)
      end
      invoice_ids.index_with { [] }.merge(summaries.group_by(&:invoice_id))
    end

    def self.to_value(invoice)
      InvoiceValue.new(**invoice.slice(*(InvoiceValue.members - [ :state ]).map(&:to_s)).symbolize_keys,
        state: invoice.draft? ? :draft : :issued)
    end
    private_class_method :to_value
  end
end
