module Sales
  # 品目カタログ。published の品目だけが、view_catalog の付与がある取引先に見える。
  # 単価は item_prices に履歴で持つ（docs/adr/006）
  class Item < TenantRecord
    TAX_RATES = [ 8, 10 ].freeze

    validates :code, :name, :unit, presence: true
    validates :tax_rate_percent, inclusion: { in: TAX_RATES }
  end
end
