class DemoWorld
  # admin に限る操作（docs/architecture/graphql-schema.md「役割による制限」の表）の公開 API を、GraphQL を通らない入口から呼ぶ口。
  # 公開 API は役割を確かめないので、mutation の基底クラスと同じく、対象を公開 API で引いてから同じ規則を操作者で評価し、
  # 拒否なら何も呼ばずに例外にする。DemoWorld は admin に限る操作をここからだけ呼ぶ（spec/scenarios/demo_world_spec.rb）
  module Operations
    class Forbidden < StandardError; end
    class NotFound < StandardError; end
    class Mismatch < StandardError; end

    # 操作ごとの、同じ操作の mutation。規則は mutation の宣言（authorization_policy・authorization_rule）から読み、
    # policy と規則の名前を書き写さない。書き写すと、mutation の規則を変えたときに、ここだけが古い規則で評価し続ける
    MUTATIONS = {
      establish_partnership: Mutations::EstablishPartnership,
      grant_permission: Mutations::GrantPermission,
      revoke_partnership: Mutations::RevokePartnership,
      request_purchase_order_cancellation: Mutations::RequestPurchaseOrderCancellation,
      inspect_inbound_shipment: Mutations::InspectInboundShipment,
      approve_cancellation_review: Mutations::ApproveCancellationReview,
      reject_cancellation_review: Mutations::RejectCancellationReview,
      cancel_sales_order: Mutations::CancelSalesOrder,
      set_billing_term: Mutations::SetBillingTerm,
      close_billing_period: Mutations::CloseBillingPeriod,
      issue_invoice: Mutations::IssueInvoice,
      schedule_item_price: Mutations::ScheduleItemPrice,
      correct_item_price: Mutations::CorrectItemPrice,
      start_import: Mutations::StartImport
    }.freeze

    def self.establish_partnership(actor, partner_code:)
      authorize!(:establish_partnership, actor)
      Partnerships::Management.establish(actor, partner_code:)
    end

    def self.grant_permission(actor, partnership_id:, permission:)
      partnership = target!(:partnership_id, Partnerships::Directory.partnership(actor, partnership_id))
      authorize!(:grant_permission, actor, partnership)
      Partnerships::Management.grant(actor, partnership_id: partnership.id, permission:)
    end

    def self.revoke_partnership(actor, partnership_id:)
      partnership = target!(:partnership_id, Partnerships::Directory.partnership(actor, partnership_id))
      authorize!(:revoke_partnership, actor, partnership)
      Partnerships::Management.revoke(actor, partnership_id: partnership.id)
    end

    def self.request_purchase_order_cancellation(actor, purchase_order_id:, reason:)
      order = target!(:purchase_order_id, Purchasing::PurchaseOrders.find(actor, purchase_order_id))
      authorize!(:request_purchase_order_cancellation, actor, order)
      Purchasing::Ordering.request_cancellation(actor, purchase_order_id: order.id, reason:)
    end

    def self.inspect_inbound_shipment(actor, inbound_shipment_id:, lines:)
      inbound = target!(:inbound_shipment_id, Purchasing::PurchaseOrders.find_inbound_shipment(actor, inbound_shipment_id))
      authorize!(:inspect_inbound_shipment, actor, inbound)
      Purchasing::ReceiptInspections.record(actor, inbound_shipment_id: inbound.id, lines:)
    end

    def self.approve_cancellation_review(actor, cancellation_review_id:)
      review = target!(:cancellation_review_id, Sales::CancellationReviews.find(actor, cancellation_review_id))
      authorize!(:approve_cancellation_review, actor, review)
      Sales::CancellationReviews.approve(actor, cancellation_review_id: review.id)
    end

    def self.reject_cancellation_review(actor, cancellation_review_id:)
      review = target!(:cancellation_review_id, Sales::CancellationReviews.find(actor, cancellation_review_id))
      authorize!(:reject_cancellation_review, actor, review)
      Sales::CancellationReviews.reject(actor, cancellation_review_id: review.id)
    end

    def self.cancel_sales_order(actor, sales_order_id:)
      order = target!(:sales_order_id, Sales::SalesOrders.find(actor, sales_order_id))
      authorize!(:cancel_sales_order, actor, order)
      Sales::OrderCancellation.cancel(actor, sales_order_id: order.id)
    end

    def self.set_billing_term(actor, customer_tenant_id:, closing_day:)
      authorize!(:set_billing_term, actor)
      Billing::Terms.set(actor, customer_tenant_id:, closing_day:)
    end

    def self.close_billing_period(actor, customer_tenant_id:, closing_date:)
      authorize!(:close_billing_period, actor)
      Billing::Closing.close(actor, customer_tenant_id:, closing_date:)
    end

    def self.issue_invoice(actor, invoice_id:)
      invoice = target!(:invoice_id, Billing::Invoices.find(actor, invoice_id))
      authorize!(:issue_invoice, actor, invoice)
      Billing::Closing.issue(actor, invoice_id: invoice.id)
    end

    def self.schedule_item_price(actor, item_id:, unit_price:, effective_on:)
      item = target!(:item_id, Sales::Catalog.item(actor, item_id))
      authorize!(:schedule_item_price, actor, item)
      Sales::ItemPrices.schedule(actor, item_id: item.id, unit_price:, effective_on:)
    end

    def self.correct_item_price(actor, item_price_id:, unit_price:, reason:)
      price = target!(:item_price_id, Sales::ItemPrices.find(actor, item_price_id))
      authorize!(:correct_item_price, actor, price)
      Sales::ItemPrices.correct(actor, item_price_id: price.id, unit_price:, reason:)
    end

    # 規則は依頼の種類を見る。品目の取り込みは admin に限り、在庫の取り込みは役割を問わない
    def self.start_import(actor, file_id:, kind:)
      request = target!(:file_id, Imports::Runs.request(actor, file_id:, kind:))
      authorize!(:start_import, actor, request)
      Imports::Runs.start(actor, request)
    end

    # 対象を引く mutation（find_target を持つ）の操作は対象に、引かない操作は操作者に評価する（mutation の基底クラスと同じ）。
    # 対象の有無が mutation と食い違えば、規則を評価せずに例外にする
    def self.authorize!(operation, actor, target = nil)
      mutation = MUTATIONS.fetch(operation)
      if targeted?(mutation) != !target.nil?
        raise Mismatch, "#{operation} の対象の有無が #{mutation.name} の find_target の有無と違う"
      end

      policy, rule = mutation.authorization_policy, mutation.authorization_rule
      return if policy.new(target || actor, user: actor).apply(rule)

      raise Forbidden, "#{policy.name}##{rule} が #{actor.role} の操作者を拒否した"
    end

    def self.targeted?(mutation) = mutation.method_defined?(:find_target) || mutation.private_method_defined?(:find_target)

    def self.target!(name, value)
      value or raise NotFound, "#{name} の対象が見えない"
    end
    private_class_method :authorize!, :targeted?, :target!
  end
end
