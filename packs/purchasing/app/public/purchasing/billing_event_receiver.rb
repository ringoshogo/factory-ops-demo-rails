module Purchasing
  # 請求からの「請求書発行」の受け手（docs/architecture/context-map.md「検収と請求の流れ」6）。
  # 発注側テナントの名義で、請求書の値を受領請求書と明細に写す。取引関係の状態は見ない。失効の前の取引も請求まで進むからである
  module BillingEventReceiver
    def self.handle(event)
      case event
      when Contracts::InvoiceIssued then receive(event)
      else raise ArgumentError, "unexpected event: #{event.class}"
      end
    end

    # 冪等キーは請求書 ID。同時に届いた配送は一意索引の ON CONFLICT で 1 件にし、見出しを書かなかった配送は明細も通知も書かない。
    # 明細の発注明細は複合外部キーで自社の発注明細に限られ、他社の発注明細を運ぶイベントは例外で失敗する。
    # 自社の admin への通知は、失うと支払いの手配が遅れて誰も気づけないので、受領請求書と同じトランザクションで確実な送信に登録する
    # （docs/adr/007 決定 5 の A-2）
    def self.receive(event)
      inserted = ReceivedInvoice.insert({ owner_tenant_id: Current.tenant_id, invoice_id: event.invoice_id,
        supplier_tenant_id: event.supplier_tenant_id, invoice_number: event.invoice_number,
        period_start: Date.iso8601(event.period_start), period_end: Date.iso8601(event.period_end),
        issued_on: Date.iso8601(event.issued_on), subtotal: Integer(event.subtotal, 10), tax_total: Integer(event.tax_total, 10),
        total: Integer(event.total, 10) }, unique_by: :invoice_id, returning: :id)
      received_invoice_id = inserted.rows.first&.first or return

      ReceivedInvoiceLine.insert_all!(event.lines.map do |line|
        { owner_tenant_id: Current.tenant_id, received_invoice_id:, purchase_order_line_id: line.fetch("purchase_order_line_id"),
          item_name: line.fetch("item_name"), unit_price: Integer(line.fetch("unit_price"), 10), quantity: line.fetch("quantity"),
          tax_rate_percent: line.fetch("tax_rate_percent"), amount: Integer(line.fetch("amount"), 10) }
      end)

      Notifications::Email.deliver_critical(:received_invoice, key: "received_invoice:#{received_invoice_id}",
        params: { invoice_number: event.invoice_number, issued_on: event.issued_on, total: event.total })
    end
    private_class_method :receive
  end
end
