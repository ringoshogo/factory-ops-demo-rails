module Sales
  # 得意先品番の照合（docs/architecture/context-map.md「発注の連結と品番の照合」2〜5）。
  # 受注を作る ACL と、対応表を登録して照合をやり直す PartMappings の両方が使う
  module PartMatching
    # 取引先ごとに、受注を作る照合と対応表の登録を直列にする。ロックを取ってから対応表を読む。
    # 直列にしないと、ACL が対応表を読んだ後・受注をコミットする前に登録が終わり、照合し直す受注を見落とす
    def self.lock(customer_tenant_id)
      SalesOrder.connection.select_value("SELECT 1 FROM pg_advisory_xact_lock(hashtextextended($1, 0))", "PartMatching",
        [ "customer_part_mappings:#{Current.tenant_id}:#{customer_tenant_id}" ])
    end

    # 得意先品番 → 自社品目。対応表と品目は自社の行だけを引く
    def self.items(customer_tenant_id, part_numbers)
      CustomerPartMapping.includes(:item)
        .where(owner_tenant_id: Current.tenant_id, customer_tenant_id:, customer_part_number: part_numbers)
        .to_h { [ _1.customer_part_number, _1.item ] }
    end

    # 受注明細に写す品目の値。品目名・税率は照合した時点のカタログの値を、単価は受注日に有効な、いま信じている単価を写し、
    # その有効日を priced_on に残す（docs/adr/006 決定 5）。prices は ItemPrice.current の行を品目 ID ごとに束ねたもの
    def self.copy(item, order_date, prices)
      return { item_id: nil, item_name: nil, unit_price: nil, priced_on: nil, tax_rate_percent: nil } unless item

      { item_id: item.id, item_name: item.name, unit_price: ItemPrice.price_on(prices[item.id], order_date), priced_on: order_date,
        tax_rate_percent: item.tax_rate_percent }
    end

    # 品目 ID ごとの現在の単価の行。明細ごとに引かず、受注をまとめて照合するときに 1 回で引く
    def self.prices(item_ids) = ItemPrice.current.where(owner_tenant_id: Current.tenant_id, item_id: item_ids).group_by(&:item_id)

    # 全明細が照合できた受注を確定し、「受注確定」を出す。発生の時刻は受注の confirmed_at で、受注・受注明細・品目の ID は運ばない。
    # 明細を読み込み済みの呼び出し元は lines に渡し、受注ごとに明細を引き直さない。
    # 自社の admin への新しい受注の通知は撃ちっぱなしにする。失っても受注は一覧に出るので、業務は進む（docs/adr/007 決定 5 の B-1）
    def self.confirm(order, lines = order.lines)
      order.update!(confirmed_at: Time.current)
      Contracts.publish(Contracts::SalesOrderConfirmed.new(
        purchase_order_id: order.source_purchase_order_id,
        buyer_tenant_id: order.customer_tenant_id,
        supplier_tenant_id: order.owner_tenant_id,
        lines: lines.map do |line|
          { "purchase_order_line_id" => line.source_purchase_order_line_id, "item_name" => line.item_name,
            "unit_price" => line.unit_price.to_s }
        end,
        occurred_at: order.confirmed_at.iso8601(6)
      ))
      Notifications::Email.deliver_best_effort(:new_sales_order, params: { order_no: order.order_no })
    end
  end
end
