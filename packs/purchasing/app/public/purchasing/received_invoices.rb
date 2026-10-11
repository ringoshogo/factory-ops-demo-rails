module Purchasing
  # 発注側が自社の受領請求書を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）
  module ReceivedInvoices
    def self.list(actor, first:, after:)
      Page.of(scope(actor), first:, after:) { |invoices| invoices.map { to_value(ReceivedInvoiceValue, _1) } }
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.find(actor, id)
      scope(actor).where(id:).first&.then { to_value(ReceivedInvoiceValue, _1) }
    end

    # 受領請求書 ID ごとの明細。見えない受領請求書の ID は空の配列になる
    def self.lines_for(actor, received_invoice_ids)
      lines = ReceivedInvoiceLine.where(received_invoice_id: scope(actor).where(id: received_invoice_ids).select(:id)).order(:id)
      received_invoice_ids.index_with { [] }.merge(lines.map { to_value(ReceivedInvoiceLineValue, _1) }.group_by(&:received_invoice_id))
    end

    def self.scope(actor) = Scope.call(actor, :own, ReceivedInvoice.all)

    def self.to_value(klass, record) = klass.new(**record.slice(*klass.members.map(&:to_s)).symbolize_keys)
    private_class_method :scope, :to_value
  end
end
