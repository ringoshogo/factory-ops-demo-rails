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

    # 未請求の明細の単価 × 検収数量の合計。税は請求書・税率ごとに 1 回だけ丸めるので、締める前の明細には税を足さない
    # （docs/architecture/data-model.md「請求（`billing`）」）。PostgreSQL の bigint の sum は numeric を返すので、整数に戻す
    def self.unbilled_total(actor)
      Scope.call(actor, BillableItem.unbilled).sum(Arel.sql("unit_price * quantity")).to_i
    end

    # 検収した受注明細を、未請求の請求対象明細として書く（docs/architecture/context-map.md「検収と請求の流れ」3）。受注が検収の記録と
    # 同じトランザクションで呼ぶ。操作者のいない入口から呼ばれるので操作者を取らず、テナントの設定を求め、所有テナントを Current のテナントで
    # 明示して書き、値を返さない（docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）。
    # 冪等キーは出荷実績 ID と受注明細 ID の組で、行があれば（請求済みでも、他社の行でも）何もしない。同時の書き込みは一意索引が止める。
    # 締めのロック（請求条件の行）は取らないので、締めの最中に書いた明細は未請求のまま残り、次の締めで集まる
    def self.confirm(customer_tenant_id:, shipment_id:, sales_order_line_id:, source_purchase_order_line_id:, item_name:, unit_price:,
      quantity:, tax_rate_percent:, inspected_on:)
      Tenancy.require_tenant!
      BillableItem.insert({ owner_tenant_id: Current.tenant_id, customer_tenant_id:, shipment_id:, sales_order_line_id:,
        source_purchase_order_line_id:, item_name:, unit_price:, quantity:, tax_rate_percent:, inspected_on: },
        unique_by: %i[shipment_id sales_order_line_id])
      nil
    end

    def self.to_value(item)
      BillableItemValue.new(**item.slice(*(BillableItemValue.members - [ :amount ]).map(&:to_s)).symbolize_keys, amount: item.amount)
    end
    private_class_method :to_value
  end
end
