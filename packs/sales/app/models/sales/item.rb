module Sales
  # 品目カタログ。published の品目だけが、view_catalog の付与がある取引先に見える。
  # 単価は item_prices に履歴で持つ（docs/adr/006）
  class Item < TenantRecord
    TAX_RATES = [ 8, 10 ].freeze

    # 消した列。移行の spec がテストの DB に列を足し直すので、無視を外すと、足し直した列を読み込んだプロセスの
    # 後の INSERT が消えた列を書いて落ちる（docs/guides/config.md「initializers/strong_migrations.rb：危険なマイグレーションを止める」）
    self.ignored_columns += [ "unit_price" ]

    validates :code, :name, :unit, presence: true
    validates :tax_rate_percent, inclusion: { in: TAX_RATES }
  end
end
