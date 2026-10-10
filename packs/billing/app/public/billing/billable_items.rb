module Billing
  # 受注側が自社の請求対象明細を読む（docs/architecture/graphql-schema.md「読み取りの一覧」）
  module BillableItems
    # 未請求の明細。取引先で絞れ、相手テナントや存在しないテナントで絞ると空になる
    def self.list(actor, customer_tenant_id:, first:, after:)
      relation = Scope.call(actor, BillableItem.unbilled)
      relation = relation.where(customer_tenant_id:) if customer_tenant_id
      Page.of(relation, first:, after:) { |items| items.map { to_value(_1) } }
    end

    # 請求書の明細。見えない請求書は空になる
    def self.for_invoice(actor, invoice_id, first:, after:)
      Page.of(Scope.call(actor, BillableItem.where(invoice_id:)), first:, after:) { |items| items.map { to_value(_1) } }
    end

    def self.to_value(item)
      BillableItemValue.new(**item.slice(*(BillableItemValue.members - [ :amount ]).map(&:to_s)).symbolize_keys, amount: item.amount)
    end
    private_class_method :to_value
  end
end
