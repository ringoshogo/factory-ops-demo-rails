module Sales
  # 品目カタログ。published の品目だけが、view_catalog の付与がある取引先に見える
  class Item < TenantRecord
    TAX_RATES = [ 8, 10 ].freeze

    validates :code, :name, :unit, presence: true
    validates :unit_price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :tax_rate_percent, inclusion: { in: TAX_RATES }
  end
end
