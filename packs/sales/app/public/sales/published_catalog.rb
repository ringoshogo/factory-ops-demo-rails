module Sales
  # 読む経路 1。受注側のカタログを、取引先向けの読み取り専用の形で公開する（docs/architecture/context-map.md「コンテキスト間の関係」）。
  # 有効な取引関係と view_catalog の付与が無ければ空を返す。購買から参照してよい sales の公開 API はこれだけである
  module PublishedCatalog
    # 相手の品目 ID をカーソルにも出さないよう、品目コードの順に並べ、コードをカーソルにする
    def self.items(actor, supplier_tenant_id:, first:, after:)
      relation = Scope.call(actor, :published_catalog, supplier_tenant_id:)
      Page.of(relation, first:, after:, key: :code, direction: :asc) do |items|
        items.map do |item|
          Item.new(supplier_tenant_id: item.owner_tenant_id, code: item.code, name: item.name, unit: item.unit,
            unit_price: item.unit_price, tax_rate_percent: item.tax_rate_percent)
        end
      end
    end
  end
end
