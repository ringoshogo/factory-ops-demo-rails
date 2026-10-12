module Sales
  # 品目カタログ。published の品目だけが、view_catalog の付与がある取引先に見える。
  # 単価は item_prices に履歴で持つ（docs/adr/006）
  class Item < TenantRecord
    TAX_RATES = [ 8, 10 ].freeze

    # 単価の正本を item_prices に移した後に消した列。消すマイグレーションの前に動いているプロセスが列を読み書きしないよう、
    # 列を消す前から無視する（strong_migrations の列を消す手順）。移行の spec が列を一時的に足し直すので、消した後も残す
    self.ignored_columns += [ "unit_price" ]

    validates :code, :name, :unit, presence: true
    validates :tax_rate_percent, inclusion: { in: TAX_RATES }
  end
end
