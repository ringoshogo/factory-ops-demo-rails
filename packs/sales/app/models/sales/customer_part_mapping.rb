module Sales
  # 得意先品番の対応表。取引先 × 得意先品番 → 自社品目。登録は M11
  class CustomerPartMapping < TenantRecord
    belongs_to :item
  end
end
