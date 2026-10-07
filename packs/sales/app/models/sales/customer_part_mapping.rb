module Sales
  # 得意先品番の対応表。取引先 × 得意先品番 → 自社品目
  class CustomerPartMapping < TenantRecord
    belongs_to :item

    validates :customer_part_number, presence: true
  end
end
