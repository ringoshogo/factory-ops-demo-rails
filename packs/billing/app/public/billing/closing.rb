module Billing
  # 請求の締めと下書きの破棄と確定（docs/architecture/data-model.md「請求（`billing`）」、
  # docs/architecture/context-map.md「検収と請求の流れ」5）。どれも請求条件の行をロックして、同じ取引先の締めと破棄と確定を直列にする。
  # 下書きが取引先ごとに 1 件であることは、部分一意索引が最後に守る。確定した請求書を変えないことは、DB のトリガーが最後に守る
  module Closing
    # 締めの入力と状態を、data-model.md の表の順に確かめ、最初に当たった結果を返す。
    # 取引先が自社の取引関係（失効したものを含む）の相手でないか、請求条件が無ければ NOT_FOUND、締め日が請求条件に当たらなければ
    # INVALID_INPUT、下書きがあれば CONFLICT、締め日が前の請求書（下書きを除く）の期間の終わり以前なら INVALID_INPUT、
    # 集める明細が無ければ CONFLICT。それ以外は、締め日以前に検収された未請求明細をすべて集めて下書きを作る。
    # 請求番号は確定で振るので、下書きは番号を持たない
    def self.close(actor, customer_tenant_id:, closing_date:)
      unless Partnerships::Directory.customer?(actor, customer_tenant_id)
        return OperationResult.failure(:not_found, path: [ :customer_tenant_id ])
      end

      Invoice.transaction(requires_new: true) do
        term = Scope.call(actor, BillingTerm.all).lock.find_by(customer_tenant_id:)
        next OperationResult.failure(:not_found, path: [ :customer_tenant_id ]) unless term
        next invalid_closing_date("Closing date must fall on the billing term's closing day") unless term.closing_date?(closing_date)

        invoices = Scope.call(actor, Invoice.where(customer_tenant_id:))
        next conflict("Customer already has a draft invoice") if invoices.draft.exists?

        previous_end = invoices.issued.maximum(:period_end)
        next invalid_closing_date("Closing date must be after the previous invoice period") if previous_end && closing_date <= previous_end

        items = Scope.call(actor, BillableItem.unbilled.where(customer_tenant_id:, inspected_on: ..closing_date)).order(:id).to_a
        next conflict("No unbilled items were inspected on or before the closing date") if items.empty?

        OperationResult.success(Invoices.find(actor, create_draft(term, items, closing_date, previous_end).id))
      end
    end

    # 下書きを消し、集めた明細を未請求に戻す。発行済みの請求書は CONFLICT
    def self.discard(actor, invoice_id:)
      invoice = Scope.call(actor, Invoice.where(id: invoice_id)).first
      return OperationResult.failure(:not_found, path: [ :invoice_id ]) unless invoice

      Invoice.transaction(requires_new: true) do
        # 締めと同じ請求条件の行をロックして、同じ取引先の締めと直列にする
        Scope.call(actor, BillingTerm.all).lock.find_by(customer_tenant_id: invoice.customer_tenant_id)
        # ロックを待つ間に、同じ下書きの別の破棄がコミットしていれば消えている
        invoice = Scope.call(actor, Invoice.where(id: invoice.id)).lock.first
        next OperationResult.failure(:not_found, path: [ :invoice_id ]) unless invoice
        next conflict("Issued invoice cannot be discarded") unless invoice.draft?

        BillableItem.where(invoice_id: invoice.id).update_all(invoice_id: nil, updated_at: Time.current)
        InvoiceTaxSummary.where(invoice_id: invoice.id).delete_all
        invoice.destroy!
        OperationResult.success(invoice.id)
      end
    end

    # 下書きに請求番号を振って確定し、「請求書発行」を出す。見えない請求書は NOT_FOUND、発行済みは CONFLICT。
    # 締め日を過ぎるのを待たずに確定できる。番号は確定と同じセーブポイントで振るので、失敗した確定は番号を使わない
    def self.issue(actor, invoice_id:)
      invoice = Scope.call(actor, Invoice.where(id: invoice_id)).first
      return OperationResult.failure(:not_found, path: [ :invoice_id ]) unless invoice

      Invoice.transaction(requires_new: true) do
        # 締めと破棄と同じ請求条件の行をロックしてから、下書きが残っているかを確かめる。ロックの前に読んだ状態で書くと、
        # 破棄でコミット済みの消えた下書きを確定するか、同じ下書きに番号を 2 回振る
        Scope.call(actor, BillingTerm.all).lock.find_by(customer_tenant_id: invoice.customer_tenant_id)
        invoice = Scope.call(actor, Invoice.where(id: invoice.id)).lock.first
        next OperationResult.failure(:not_found, path: [ :invoice_id ]) unless invoice
        next conflict("Invoice is already issued") unless invoice.draft?

        invoice.update!(invoice_number: DocumentNumber.next(InvoiceSequence, prefix: "INV"), issued_at: Time.current)
        publish_issued(invoice)
        OperationResult.success(Invoices.find(actor, invoice.id))
      end
    end

    def self.publish_issued(invoice)
      Contracts.publish(Contracts::InvoiceIssued.new(
        invoice_id: invoice.id, supplier_tenant_id: invoice.owner_tenant_id, buyer_tenant_id: invoice.customer_tenant_id,
        invoice_number: invoice.invoice_number, period_start: invoice.period_start.iso8601, period_end: invoice.period_end.iso8601,
        issued_on: invoice.issued_at.to_date.iso8601, subtotal: invoice.subtotal.to_s, tax_total: invoice.tax_total.to_s,
        total: invoice.total.to_s,
        lines: invoice.items.map do |item|
          { "purchase_order_line_id" => item.source_purchase_order_line_id, "item_name" => item.item_name,
            "unit_price" => item.unit_price.to_s, "quantity" => item.quantity, "tax_rate_percent" => item.tax_rate_percent,
            "amount" => item.amount.to_s }
        end
      ))
    end

    # 期間の終わりは締め日、始まりは前の請求書の終わりの翌日（無ければ集めた明細の最も古い検収日）。
    # 期間は表示のためのもので、始まりより前に検収された遅れた明細も集める。
    # 税は税率ごとに課税対象額を足し上げてから 1 回だけ切り捨てる。明細ごとに丸めて足すと、適格請求書の要件を満たさない
    def self.create_draft(term, items, closing_date, previous_end)
      summaries = items.group_by(&:tax_rate_percent).sort.map do |rate, rate_items|
        taxable = rate_items.sum(&:amount)
        { tax_rate_percent: rate, taxable_amount: taxable, tax_amount: taxable * rate / 100 }
      end
      subtotal = summaries.sum { _1[:taxable_amount] }
      tax_total = summaries.sum { _1[:tax_amount] }
      invoice = Invoice.create!(owner_tenant_id: term.owner_tenant_id, customer_tenant_id: term.customer_tenant_id,
        period_start: previous_end&.next_day || items.map(&:inspected_on).min, period_end: closing_date,
        subtotal:, tax_total:, total: subtotal + tax_total)
      summaries.each { invoice.tax_summaries.create!(owner_tenant_id: invoice.owner_tenant_id, **_1) }
      # 集めた明細だけを ID で請求書に結ぶ。条件で引き直すと、締めの最中に届いた明細まで結ぶ
      BillableItem.where(id: items.map(&:id)).update_all(invoice_id: invoice.id, updated_at: Time.current)
      invoice
    end

    def self.invalid_closing_date(message) = OperationResult.failure(:invalid_input, path: [ :closing_date ], message:)
    def self.conflict(message) = OperationResult.failure(:conflict, message:)
    private_class_method :publish_issued, :create_draft, :invalid_closing_date, :conflict
  end
end
