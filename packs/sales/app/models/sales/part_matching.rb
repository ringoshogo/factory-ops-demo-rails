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

    # 受注明細に写す品目の値。単価・品目名・税率は照合した時点のカタログの値を写す
    def self.copy(item)
      { item_id: item&.id, item_name: item&.name, unit_price: item&.unit_price, tax_rate_percent: item&.tax_rate_percent }
    end

    # 全明細が照合できた受注を確定し、「受注確定」を出す。受注・受注明細・品目の ID は運ばない。
    # 明細を読み込み済みの呼び出し元は lines に渡し、受注ごとに明細を引き直さない
    def self.confirm(order, lines = order.lines)
      order.update!(confirmed_at: Time.current)
      Contracts.publish(Contracts::SalesOrderConfirmed.new(
        purchase_order_id: order.source_purchase_order_id,
        buyer_tenant_id: order.customer_tenant_id,
        supplier_tenant_id: order.owner_tenant_id,
        lines: lines.map do |line|
          { "purchase_order_line_id" => line.source_purchase_order_line_id, "item_name" => line.item_name,
            "unit_price" => line.unit_price.to_s }
        end
      ))
    end
  end
end
