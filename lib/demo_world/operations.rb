class DemoWorld
  # admin に限る操作（docs/architecture/graphql-schema.md「役割による制限」の表）の公開 API を、GraphQL を通らない入口から呼ぶ口。
  # 公開 API は役割を確かめないので、mutation の基底クラスと同じく、対象を公開 API で引いてから同じ policy の規則を操作者で評価し、
  # 拒否なら何も呼ばずに例外にする。DemoWorld は admin に限る操作をここからだけ呼ぶ（spec/scenarios/demo_world_spec.rb）
  module Operations
    class Forbidden < StandardError; end
    class NotFound < StandardError; end

    def self.establish_partnership(actor, partner_code:)
      authorize!(actor, Partnerships::PartnershipPolicy, :establish?)
      Partnerships::Management.establish(actor, partner_code:)
    end

    def self.grant_permission(actor, partnership_id:, permission:)
      partnership = target!(:partnership_id, Partnerships::Directory.partnership(actor, partnership_id))
      authorize!(actor, Partnerships::PartnershipPolicy, :manage?, partnership)
      Partnerships::Management.grant(actor, partnership_id: partnership.id, permission:)
    end

    def self.revoke_partnership(actor, partnership_id:)
      partnership = target!(:partnership_id, Partnerships::Directory.partnership(actor, partnership_id))
      authorize!(actor, Partnerships::PartnershipPolicy, :manage?, partnership)
      Partnerships::Management.revoke(actor, partnership_id: partnership.id)
    end

    def self.request_purchase_order_cancellation(actor, purchase_order_id:, reason:)
      order = target!(:purchase_order_id, Purchasing::PurchaseOrders.find(actor, purchase_order_id))
      authorize!(actor, Purchasing::PurchaseOrderPolicy, :request_cancellation?, order)
      Purchasing::Ordering.request_cancellation(actor, purchase_order_id: order.id, reason:)
    end

    def self.inspect_inbound_shipment(actor, inbound_shipment_id:, lines:)
      inbound = target!(:inbound_shipment_id, Purchasing::PurchaseOrders.find_inbound_shipment(actor, inbound_shipment_id))
      authorize!(actor, Purchasing::PurchaseOrderPolicy, :inspect_receipt?, inbound)
      Purchasing::ReceiptInspections.record(actor, inbound_shipment_id: inbound.id, lines:)
    end

    def self.approve_cancellation_review(actor, cancellation_review_id:)
      review = target!(:cancellation_review_id, Sales::CancellationReviews.find(actor, cancellation_review_id))
      authorize!(actor, Sales::SalesOrderPolicy, :review?, review)
      Sales::CancellationReviews.approve(actor, cancellation_review_id: review.id)
    end

    def self.reject_cancellation_review(actor, cancellation_review_id:)
      review = target!(:cancellation_review_id, Sales::CancellationReviews.find(actor, cancellation_review_id))
      authorize!(actor, Sales::SalesOrderPolicy, :review?, review)
      Sales::CancellationReviews.reject(actor, cancellation_review_id: review.id)
    end

    def self.cancel_sales_order(actor, sales_order_id:)
      order = target!(:sales_order_id, Sales::SalesOrders.find(actor, sales_order_id))
      authorize!(actor, Sales::SalesOrderPolicy, :cancel?, order)
      Sales::OrderCancellation.cancel(actor, sales_order_id: order.id)
    end

    def self.set_billing_term(actor, customer_tenant_id:, closing_day:)
      authorize!(actor, Billing::InvoicePolicy, :set_term?)
      Billing::Terms.set(actor, customer_tenant_id:, closing_day:)
    end

    def self.close_billing_period(actor, customer_tenant_id:, closing_date:)
      authorize!(actor, Billing::InvoicePolicy, :close?)
      Billing::Closing.close(actor, customer_tenant_id:, closing_date:)
    end

    def self.issue_invoice(actor, invoice_id:)
      invoice = target!(:invoice_id, Billing::Invoices.find(actor, invoice_id))
      authorize!(actor, Billing::InvoicePolicy, :issue?, invoice)
      Billing::Closing.issue(actor, invoice_id: invoice.id)
    end

    def self.schedule_item_price(actor, item_id:, unit_price:, effective_on:)
      item = target!(:item_id, Sales::Catalog.item(actor, item_id))
      authorize!(actor, Sales::ItemPolicy, :change_price?, item)
      Sales::ItemPrices.schedule(actor, item_id: item.id, unit_price:, effective_on:)
    end

    def self.correct_item_price(actor, item_price_id:, unit_price:, reason:)
      price = target!(:item_price_id, Sales::ItemPrices.find(actor, item_price_id))
      authorize!(actor, Sales::ItemPolicy, :change_price?, price)
      Sales::ItemPrices.correct(actor, item_price_id: price.id, unit_price:, reason:)
    end

    # 規則は依頼の種類を見る。品目の取り込みは admin に限り、在庫の取り込みは役割を問わない
    def self.start_import(actor, file_id:, kind:)
      request = target!(:file_id, Imports::Runs.request(actor, file_id:, kind:))
      authorize!(actor, Imports::ImportPolicy, :start?, request)
      Imports::Runs.start(actor, request)
    end

    # 対象の無い操作は、操作者に対して評価する（mutation の基底クラスと同じ）
    def self.authorize!(actor, policy, rule, record = nil)
      return if policy.new(record, user: actor).apply(rule)

      raise Forbidden, "#{policy.name}##{rule} が #{actor.role} の操作者を拒否した"
    end

    def self.target!(name, value)
      value or raise NotFound, "#{name} の対象が見えない"
    end
    private_class_method :authorize!, :target!
  end
end
